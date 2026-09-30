import numpy as np, soundfile as sf, subprocess, os, glob

stems_dir = "separated/htdemucs_6s/input"
# decode original m4a to wav array via ffmpeg pipe
def load_ffmpeg(path, sr=44100):
    import io
    cmd=["ffmpeg","-v","error","-i",path,"-ac","2","-ar",str(sr),"-f","f32le","-"]
    raw=subprocess.run(cmd,capture_output=True).stdout
    a=np.frombuffer(raw,dtype=np.float32).reshape(-1,2)
    return a, sr

orig,sr = load_ffmpeg("input.m4a")
n=orig.shape[0]

def rms_db(x):
    r=np.sqrt(np.mean(x**2)+1e-12)
    return 20*np.log10(r+1e-12)
def peak_db(x):
    return 20*np.log10(np.max(np.abs(x))+1e-12)

orig_rms = rms_db(orig)
print(f"{'STEM':8} {'RMS dBFS':>9} {'PEAK dBFS':>10} {'ENERGY %':>9}")
print("-"*40)
stems={}
tot_energy=0
data={}
for f in ["vocals","drums","bass","guitar","piano","other"]:
    x,_=sf.read(os.path.join(stems_dir,f+".mp3"))
    if x.ndim==1: x=np.stack([x,x],1)
    data[f]=x
    tot_energy+=np.sum(x**2)
for f in ["vocals","drums","bass","guitar","piano","other"]:
    x=data[f]
    e=np.sum(x**2)
    print(f"{f:8} {rms_db(x):9.1f} {peak_db(x):10.1f} {100*e/tot_energy:8.1f}%")
print("-"*40)
print(f"{'ORIGINAL':8} {orig_rms:9.1f} {peak_db(orig):10.1f}")

# reconstruction: sum stems vs original (align length)
m=min(n, min(v.shape[0] for v in data.values()))
s=sum(v[:m] for v in data.values())
o=orig[:m]
resid=o-s
print(f"\nReconstruction (sum of 6 stems vs original):")
print(f"  residual RMS: {rms_db(resid):.1f} dBFS  (original {rms_db(o):.1f} dBFS)")
print(f"  -> lower residual = stems faithfully sum to original")
