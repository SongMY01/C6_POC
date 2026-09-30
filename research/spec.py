import numpy as np, soundfile as sf, subprocess, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sr=44100
def load_ffmpeg(path):
    cmd=["ffmpeg","-v","error","-i",path,"-ac","1","-ar",str(sr),"-f","f32le","-"]
    raw=subprocess.run(cmd,capture_output=True).stdout
    return np.frombuffer(raw,dtype=np.float32)

d="separated/htdemucs_6s/input"
tracks=[("ORIGINAL (mix)","input.m4a")]+[(n.upper(),os.path.join(d,f+".mp3")) for n,f in
    [("vocals","vocals"),("drums","drums"),("bass","bass"),("guitar","guitar"),("piano","piano"),("other","other")]]

# analyze a representative 20s window (60-80s)
t0,t1=60,80
fig,axes=plt.subplots(len(tracks),1,figsize=(12,14),sharex=True)
for ax,(name,path) in zip(axes,tracks):
    y=load_ffmpeg(path)
    seg=y[int(t0*sr):int(t1*sr)]
    ax.specgram(seg,NFFT=2048,Fs=sr,noverlap=1024,cmap="magma",vmin=-120,vmax=-20)
    ax.set_ylim(0,8000)
    ax.set_ylabel(name,rotation=0,ha="right",va="center",fontsize=9)
    ax.set_yticks([])
axes[-1].set_xlabel("time (s), window 60-80s")
plt.suptitle("htdemucs_6s stem separation — spectrograms (0-8kHz)",fontsize=12)
plt.tight_layout()
plt.savefig("spectrograms.png",dpi=110,bbox_inches="tight")
print("saved spectrograms.png")

# accurate reconstruction with delay alignment (decode stems as f32, align by xcorr)
def load_stereo(path):
    cmd=["ffmpeg","-v","error","-i",path,"-ac","2","-ar",str(sr),"-f","f32le","-"]
    raw=subprocess.run(cmd,capture_output=True).stdout
    return np.frombuffer(raw,dtype=np.float32).reshape(-1,2)
orig=load_stereo("input.m4a")
stems=[load_stereo(os.path.join(d,f+".mp3")) for f in ["vocals","drums","bass","guitar","piano","other"]]
m=min([orig.shape[0]]+[s.shape[0] for s in stems])
s=sum(x[:m] for x in stems); o=orig[:m]
# find best integer delay via xcorr on mono slice
a=o[:sr*10,0]; b=s[:sr*10,0]
corr=np.correlate(a-a.mean(), b-b.mean(), mode="full")
lag=np.argmax(corr)-(len(b)-1)
if lag>0: s2=s[:-lag] if lag<m else s; o2=o[lag:lag+len(s2)]
elif lag<0: o2=o[:lag]; s2=s[-lag:-lag+len(o2)]
else: s2,o2=s,o
L=min(len(s2),len(o2)); s2,o2=s2[:L],o2[:L]
def rms_db(x): return 20*np.log10(np.sqrt(np.mean(x**2))+1e-12)
print(f"delay-aligned lag={lag} samples")
print(f"residual RMS: {rms_db(o2-s2):.1f} dBFS | original {rms_db(o2):.1f} dBFS | diff {rms_db(o2)-rms_db(o2-s2):.1f} dB below signal")
