"""
POC: 합주 녹음 → 세션별 음원 분리 서버

iPad Swift 앱이 통합 녹음 파일을 업로드하면, 이미 검증한 Demucs(htdemucs_6s)
파이프라인으로 6개 스템(vocals/drums/bass/guitar/piano/other)을 분리해
개별 파일로 내려준다.

흐름:
  POST /jobs            (multipart file)  -> {job_id}
  GET  /jobs/{job_id}                      -> {status, stems:[...]}
  GET  /jobs/{job_id}/stems/{name}.mp3     -> 오디오 바이너리

분리는 백그라운드 스레드에서 실행되고, 클라이언트는 status를 폴링한다.

여러 iPad 동기화(sync.py): 이 서버가 피드백·재녹음 패치·공유 곡의 기준 저장소 역할을 한다.
"""
import shutil
import subprocess
import sys
import threading
import uuid
from pathlib import Path
from typing import Dict

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware

from server.sync import router as sync_router, set_song_job, current_song_job


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
DATA_DIR.mkdir(exist_ok=True)

# 실제 밴드 편성에 맞춰 5개만 노출 (other는 앱에서 숨김)
EXPOSED_STEMS = ["vocals", "drums", "bass", "guitar", "piano"]
MODEL_NAME = "htdemucs_6s"

app = FastAPI(title="Band Session Separator POC")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(sync_router)

# job_id -> {"status": "queued"|"processing"|"done"|"error", "error": str|None, "stems_dir": Path|None}
JOBS: Dict[str, dict] = {}
JOBS_LOCK = threading.Lock()


def run_separation(job_id: str, input_path: Path):
    job_dir = DATA_DIR / job_id
    try:
        with JOBS_LOCK:
            JOBS[job_id]["status"] = "processing"

        cmd = [
            sys.executable, "-m", "demucs",
            "-n", MODEL_NAME,
            "-d", "mps",
            "--mp3", "--mp3-bitrate", "320",
            "-o", str(job_dir / "out"),
            str(input_path),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(result.stderr[-2000:])

        # demucs가 out/htdemucs_6s/<입력파일명(확장자 제외)>/ 아래에 stem들을 씀
        stem_name = input_path.stem
        produced_dir = job_dir / "out" / MODEL_NAME / stem_name
        if not produced_dir.exists():
            raise RuntimeError(f"expected output dir not found: {produced_dir}")

        final_dir = job_dir / "stems"
        final_dir.mkdir(parents=True, exist_ok=True)
        for stem in EXPOSED_STEMS:
            src = produced_dir / f"{stem}.mp3"
            if src.exists():
                shutil.copy(src, final_dir / f"{stem}.mp3")

        with JOBS_LOCK:
            JOBS[job_id]["status"] = "done"
            JOBS[job_id]["stems_dir"] = final_dir
        # 가장 최근에 분리한 곡을 모든 iPad가 함께 쓰는 "공유 곡"으로 지정
        set_song_job(job_id)
    except Exception as e:  # noqa: BLE001
        with JOBS_LOCK:
            JOBS[job_id]["status"] = "error"
            JOBS[job_id]["error"] = str(e)


def restore_finished_jobs():
    """서버를 재시작해도 이전에 분리해 둔 곡(특히 공유 곡)을 다시 내려받을 수 있게 한다."""
    for job_dir in DATA_DIR.iterdir():
        stems_dir = job_dir / "stems"
        if job_dir.is_dir() and stems_dir.is_dir():
            JOBS[job_dir.name] = {"status": "done", "error": None, "stems_dir": stems_dir}
    # 공유 곡이 아직 없으면 가장 최근에 분리한 곡으로
    if current_song_job() is None:
        done = [d for d in DATA_DIR.iterdir() if (d / "stems").is_dir()]
        if done:
            set_song_job(max(done, key=lambda d: d.stat().st_mtime).name)


restore_finished_jobs()


@app.post("/jobs")
async def create_job(file: UploadFile = File(...)):
    job_id = uuid.uuid4().hex[:12]
    job_dir = DATA_DIR / job_id
    job_dir.mkdir(parents=True, exist_ok=True)

    suffix = Path(file.filename or "input.m4a").suffix or ".m4a"
    input_path = job_dir / f"input{suffix}"
    with open(input_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    with JOBS_LOCK:
        JOBS[job_id] = {"status": "queued", "error": None, "stems_dir": None}

    thread = threading.Thread(target=run_separation, args=(job_id, input_path), daemon=True)
    thread.start()

    return {"job_id": job_id}


@app.get("/jobs/{job_id}")
async def get_job(job_id: str):
    with JOBS_LOCK:
        job = JOBS.get(job_id)
    if job is None:
        raise HTTPException(404, "job not found")

    resp = {"job_id": job_id, "status": job["status"]}
    if job["status"] == "error":
        resp["error"] = job["error"]
    if job["status"] == "done":
        resp["stems"] = [s for s in EXPOSED_STEMS if (job["stems_dir"] / f"{s}.mp3").exists()]
    return resp


@app.get("/jobs/{job_id}/stems/{stem_name}.mp3")
async def get_stem(job_id: str, stem_name: str):
    with JOBS_LOCK:
        job = JOBS.get(job_id)
    if job is None or job["status"] != "done":
        raise HTTPException(404, "stem not ready")
    if stem_name not in EXPOSED_STEMS:
        raise HTTPException(404, "unknown stem")
    path = job["stems_dir"] / f"{stem_name}.mp3"
    if not path.exists():
        raise HTTPException(404, "stem file missing")
    return FileResponse(path, media_type="audio/mpeg")


@app.get("/health")
async def health():
    return {"ok": True, "model": MODEL_NAME}
