"""
다음 합주 시각 설정 / 팀 연습 시작 현황 초기화 (버전 B의 D-day 링에 쓰임).

  python tools/set_rehearsal.py 3          3일 뒤로 설정 (오늘 기준 N일 뒤 같은 시각)
  python tools/set_rehearsal.py reset      "연습을 시작한 사람" 현황만 초기화
  python tools/set_rehearsal.py 3 reset    둘 다
"""
import json
import sys
import time
import urllib.request

server = "http://127.0.0.1:8756"
args = sys.argv[1:]
body = {}
for a in args:
    if a == "reset":
        body["reset"] = True
    else:
        body["nextRehearsal"] = time.time() + float(a) * 86400
if not body:
    sys.exit(__doc__)
req = urllib.request.Request(server + "/sync/admin/rehearsal", data=json.dumps(body).encode(), method="POST",
                             headers={"Content-Type": "application/json"})
print(urllib.request.urlopen(req, timeout=5).read().decode())
