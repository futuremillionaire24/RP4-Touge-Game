"""Objective checks for rendered engine audio: level, clipping, pitch tracking, spectrogram PNG.
Usage: python tools/analyze_audio.py build/audio/*.wav
"""
import sys
import glob
import numpy as np
from scipy.io import wavfile
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

files = []
for a in sys.argv[1:]:
    files += glob.glob(a)
fig, axes = plt.subplots(len(files), 1, figsize=(12, 3.2 * len(files)), squeeze=False)
for ax, path in zip(axes[:, 0], files):
    fs, data = wavfile.read(path)
    x = data.astype(np.float64)
    if x.ndim > 1:
        x = x.mean(axis=1)
    if data.dtype == np.int16:
        x /= 32768.0
    seg = int(fs * 0.25)
    rms = [np.sqrt(np.mean(x[i:i + seg] ** 2)) for i in range(0, len(x) - seg, seg)]
    clip = np.mean(np.abs(x) > 0.98) * 100
    # Dominant frequency (80-2000 Hz) per 0.5 s window -> should rise through the sweep.
    win = int(fs * 0.5)
    dom = []
    for i in range(0, len(x) - win, win):
        s = np.abs(np.fft.rfft(x[i:i + win] * np.hanning(win)))
        f = np.fft.rfftfreq(win, 1 / fs)
        m = (f > 60) & (f < 2000)
        dom.append(int(f[m][np.argmax(s[m])]))
    name = path.replace("\\", "/").split("/")[-1]
    print(f"{name}: peak {np.max(np.abs(x)):.2f}  clip {clip:.2f}%  rms min/max {min(rms):.3f}/{max(rms):.3f}")
    print(f"   dominant Hz per 0.5 s: {dom}")
    ax.specgram(x, NFFT=2048, Fs=fs, noverlap=1536, cmap="magma", vmin=-110)
    ax.set_ylim(0, 6000)
    ax.set_title(name)
plt.tight_layout()
out = "build/audio/spectrograms.png"
plt.savefig(out, dpi=70)
print("saved", out)
