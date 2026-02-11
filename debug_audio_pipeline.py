#!/usr/bin/env python3
"""
WaveDrop Audio Pipeline Debugger
Uses librosa to analyze audio files and compare against the Swift implementation.

Usage:
    python debug_audio_pipeline.py <audio_file>
    python debug_audio_pipeline.py <audio_file> --plot
    python debug_audio_pipeline.py <directory>  # analyze all audio files in dir
"""

import sys
import os
import json
import argparse
from pathlib import Path

import numpy as np
import librosa
import soundfile as sf


# ---------------------------------------------------------------------------
# BPM Detection (mirrors Swift's calculateBPM autocorrelation approach)
# ---------------------------------------------------------------------------

def detect_bpm_autocorrelation(y, sr, min_bpm=60, max_bpm=200):
    """
    Replicate the Swift autocorrelation-based BPM detection.
    This is what WaveDrop currently does - basic autocorrelation on raw audio.
    """
    min_lag = int(60.0 / max_bpm * sr)
    max_lag = int(60.0 / min_bpm * sr)

    max_correlation = 0.0
    best_lag = min_lag

    # Limit analysis to first 30s for performance (like the Swift version processes full file)
    analysis_length = min(len(y), sr * 30)
    y_analysis = y[:analysis_length]

    for lag in range(min_lag, min(max_lag, analysis_length // 2)):
        correlation = np.sum(y_analysis[:analysis_length - lag] * y_analysis[lag:analysis_length])
        if correlation > max_correlation:
            max_correlation = correlation
            best_lag = lag

    bpm = 60.0 * sr / best_lag
    return bpm


def detect_bpm_librosa(y, sr):
    """
    Use librosa's beat tracking - much more accurate than raw autocorrelation.
    This is what WaveDrop SHOULD be using.
    """
    tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr)
    # librosa may return an array; extract scalar
    if hasattr(tempo, '__len__'):
        tempo = float(tempo[0]) if len(tempo) > 0 else 0.0
    return float(tempo), beat_frames


def detect_bpm_onset(y, sr):
    """
    Alternative: onset-based tempo estimation.
    """
    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    tempo = librosa.feature.tempo(onset_envelope=onset_env, sr=sr)
    if hasattr(tempo, '__len__'):
        tempo = float(tempo[0]) if len(tempo) > 0 else 0.0
    return float(tempo)


# ---------------------------------------------------------------------------
# Key Detection (WaveDrop stub always returns C major!)
# ---------------------------------------------------------------------------

KEY_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']

# Krumhansl-Schmuckler key profiles
MAJOR_PROFILE = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
MINOR_PROFILE = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])

# Camelot Wheel mapping
CAMELOT_MAJOR = {
    'C': '8B', 'G': '9B', 'D': '10B', 'A': '11B', 'E': '12B', 'B': '1B',
    'F#': '2B', 'C#': '3B', 'G#': '4B', 'D#': '5B', 'A#': '6B', 'F': '7B'
}
CAMELOT_MINOR = {
    'A': '8A', 'E': '9A', 'B': '10A', 'F#': '11A', 'C#': '12A', 'G#': '1A',
    'D#': '2A', 'A#': '3A', 'F': '4A', 'C': '5A', 'G': '6A', 'D': '7A'
}


def detect_key_krumhansl(y, sr):
    """
    Krumhansl-Schmuckler key detection algorithm.
    This is what WaveDrop's detectKey() SHOULD implement (currently a stub).
    """
    # Compute chromagram
    chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
    # Average across time to get pitch class distribution
    chroma_avg = np.mean(chroma, axis=1)

    # Normalize
    chroma_avg = chroma_avg / (np.sum(chroma_avg) + 1e-10)

    best_corr = -1
    best_key = 'C'
    best_scale = 'major'

    for i in range(12):
        # Rotate profile to match each possible root note
        major_shifted = np.roll(MAJOR_PROFILE, i)
        minor_shifted = np.roll(MINOR_PROFILE, i)

        # Normalize profiles
        major_shifted = major_shifted / np.sum(major_shifted)
        minor_shifted = minor_shifted / np.sum(minor_shifted)

        # Pearson correlation
        major_corr = np.corrcoef(chroma_avg, major_shifted)[0, 1]
        minor_corr = np.corrcoef(chroma_avg, minor_shifted)[0, 1]

        if major_corr > best_corr:
            best_corr = major_corr
            best_key = KEY_NAMES[i]
            best_scale = 'major'

        if minor_corr > best_corr:
            best_corr = minor_corr
            best_key = KEY_NAMES[i]
            best_scale = 'minor'

    camelot = CAMELOT_MAJOR.get(best_key, '?') if best_scale == 'major' else CAMELOT_MINOR.get(best_key, '?')

    return best_key, best_scale, camelot, best_corr


# ---------------------------------------------------------------------------
# Waveform Generation (mirrors Swift's downsampleToWaveform)
# ---------------------------------------------------------------------------

def generate_waveform_swift_style(y, target_samples=1000):
    """
    Replicate the Swift downsampleToWaveform - peak amplitude per bin.
    """
    frame_count = len(y)
    samples_per_bin = frame_count // target_samples
    waveform = []

    for i in range(target_samples):
        start = i * samples_per_bin
        end = min(start + samples_per_bin, frame_count)
        max_amplitude = float(np.max(np.abs(y[start:end])))
        waveform.append(max_amplitude)

    return waveform


def generate_waveform_rms(y, target_samples=1000):
    """
    Better waveform using RMS (root mean square) - smoother and more representative.
    """
    frame_count = len(y)
    hop_length = frame_count // target_samples
    rms = librosa.feature.rms(y=y, frame_length=hop_length * 2, hop_length=hop_length)[0]
    # Resample to exact target_samples
    if len(rms) > target_samples:
        rms = rms[:target_samples]
    return rms.tolist()


# ---------------------------------------------------------------------------
# Metadata Extraction
# ---------------------------------------------------------------------------

def extract_metadata(filepath):
    """Extract audio file metadata."""
    info = sf.info(filepath)
    return {
        'format': info.format,
        'subtype': info.subtype,
        'channels': info.channels,
        'samplerate': info.samplerate,
        'frames': info.frames,
        'duration_seconds': info.duration,
        'duration_formatted': f"{int(info.duration // 60)}:{int(info.duration % 60):02d}",
    }


# ---------------------------------------------------------------------------
# Full Pipeline Analysis
# ---------------------------------------------------------------------------

def analyze_file(filepath, plot=False):
    """Run the full audio analysis pipeline on a single file."""
    filepath = str(filepath)
    filename = os.path.basename(filepath)

    print(f"\n{'='*70}")
    print(f"  WAVEDROP AUDIO PIPELINE DEBUG: {filename}")
    print(f"{'='*70}")

    # 1. Load audio
    print("\n[1/5] Loading audio...")
    try:
        y, sr = librosa.load(filepath, sr=None, mono=True)
    except Exception as e:
        print(f"  ERROR loading file: {e}")
        return None

    duration = len(y) / sr
    print(f"  Sample rate: {sr} Hz")
    print(f"  Duration: {duration:.2f}s ({int(duration//60)}:{int(duration%60):02d})")
    print(f"  Samples: {len(y):,}")

    # 2. Metadata
    print("\n[2/5] Extracting metadata...")
    try:
        meta = extract_metadata(filepath)
        for k, v in meta.items():
            print(f"  {k}: {v}")
    except Exception as e:
        print(f"  WARNING: Could not extract metadata: {e}")
        meta = {}

    # 3. BPM Detection
    print("\n[3/5] BPM Detection...")
    print("  --- Swift's method (autocorrelation on raw audio) ---")
    bpm_autocorr = detect_bpm_autocorrelation(y, sr)
    print(f"  BPM (autocorrelation): {bpm_autocorr:.1f}")

    print("  --- librosa beat_track (recommended replacement) ---")
    bpm_librosa, beat_frames = detect_bpm_librosa(y, sr)
    print(f"  BPM (librosa beat_track): {bpm_librosa:.1f}")
    print(f"  Beat frames detected: {len(beat_frames)}")

    print("  --- librosa onset tempo ---")
    bpm_onset = detect_bpm_onset(y, sr)
    print(f"  BPM (onset strength): {bpm_onset:.1f}")

    bpm_diff = abs(bpm_autocorr - bpm_librosa)
    if bpm_diff > 10:
        print(f"\n  !! BPM MISMATCH: autocorr={bpm_autocorr:.1f} vs librosa={bpm_librosa:.1f} (diff={bpm_diff:.1f})")
        print(f"  !! The Swift autocorrelation method is likely INACCURATE for this track")
    else:
        print(f"\n  OK: BPM methods agree within {bpm_diff:.1f} BPM")

    # 4. Key Detection
    print("\n[4/5] Key Detection...")
    print("  --- Swift's method (STUB - always returns C major / 8B) ---")
    print(f"  Key (Swift stub): C major (8B)")

    print("  --- Krumhansl-Schmuckler (proper implementation) ---")
    key_name, key_scale, camelot, confidence = detect_key_krumhansl(y, sr)
    print(f"  Key (K-S algorithm): {key_name} {key_scale} ({camelot})")
    print(f"  Confidence: {confidence:.3f}")
    if camelot != '8B':
        print(f"  !! KEY MISMATCH: Swift stub returns 8B, actual key is {camelot}")
    else:
        print(f"  Note: Swift stub accidentally correct (track is in C major)")

    # 5. Waveform
    print("\n[5/5] Waveform Generation...")
    waveform_peak = generate_waveform_swift_style(y, target_samples=100)
    waveform_rms = generate_waveform_rms(y, target_samples=100)
    print(f"  Peak waveform (Swift style): {len(waveform_peak)} samples, "
          f"range [{min(waveform_peak):.4f}, {max(waveform_peak):.4f}]")
    print(f"  RMS waveform (recommended):  {len(waveform_rms)} samples, "
          f"range [{min(waveform_rms):.4f}, {max(waveform_rms):.4f}]")

    # Summary
    print(f"\n{'='*70}")
    print("  DIAGNOSIS SUMMARY")
    print(f"{'='*70}")
    issues = []
    if bpm_diff > 10:
        issues.append(f"BPM: autocorrelation gives {bpm_autocorr:.1f}, should be ~{bpm_librosa:.1f}")
    if camelot != '8B':
        issues.append(f"Key: stub returns C major (8B), actual is {key_name} {key_scale} ({camelot})")
    else:
        issues.append("Key: stub always returns C major - NEEDS real implementation even if correct here")

    if issues:
        print(f"\n  Found {len(issues)} issue(s):")
        for i, issue in enumerate(issues, 1):
            print(f"    {i}. {issue}")
    else:
        print("\n  No major issues detected (but key detection is still a stub)")

    print(f"\n  RECOMMENDED FIXES for AudioMetadataExtractor.swift:")
    print(f"    1. Replace calculateBPM() with onset-based beat tracking")
    print(f"    2. Implement detectKey() using Krumhansl-Schmuckler (chromagram + correlation)")
    print(f"    3. Consider RMS waveform instead of peak amplitude")

    # Build results dict
    results = {
        'file': filename,
        'duration': duration,
        'sample_rate': sr,
        'bpm_autocorrelation': round(bpm_autocorr, 1),
        'bpm_librosa': round(bpm_librosa, 1),
        'bpm_onset': round(bpm_onset, 1),
        'key': f"{key_name} {key_scale}",
        'camelot': camelot,
        'key_confidence': round(confidence, 3),
        'metadata': meta,
    }

    # Optional plotting
    if plot:
        try:
            import matplotlib
            matplotlib.use('Agg')
            import matplotlib.pyplot as plt

            fig, axes = plt.subplots(4, 1, figsize=(14, 12))
            fig.suptitle(f'WaveDrop Debug: {filename}', fontsize=14, fontweight='bold')

            # Waveform
            times = np.linspace(0, duration, len(y))
            axes[0].plot(times, y, linewidth=0.3, color='#2196F3')
            axes[0].set_title('Raw Waveform')
            axes[0].set_xlabel('Time (s)')
            axes[0].set_ylabel('Amplitude')

            # Beat tracking
            beat_times = librosa.frames_to_time(beat_frames, sr=sr)
            axes[1].plot(times, y, linewidth=0.3, color='#9E9E9E')
            for bt in beat_times:
                axes[1].axvline(x=bt, color='#F44336', alpha=0.5, linewidth=0.5)
            axes[1].set_title(f'Beat Tracking (BPM: {bpm_librosa:.1f})')
            axes[1].set_xlabel('Time (s)')

            # Chromagram
            chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
            img = librosa.display.specshow(chroma, y_axis='chroma', x_axis='time', sr=sr, ax=axes[2])
            axes[2].set_title(f'Chromagram (Key: {key_name} {key_scale} / {camelot})')
            fig.colorbar(img, ax=axes[2])

            # Waveform comparison
            x_peak = np.linspace(0, duration, len(waveform_peak))
            x_rms = np.linspace(0, duration, len(waveform_rms))
            axes[3].fill_between(x_peak, waveform_peak, alpha=0.4, color='#FF9800', label='Peak (Swift)')
            axes[3].plot(x_rms, waveform_rms, color='#4CAF50', linewidth=1.5, label='RMS (recommended)')
            axes[3].set_title('Waveform Visualization Comparison')
            axes[3].set_xlabel('Time (s)')
            axes[3].legend()

            plt.tight_layout()
            plot_path = filepath.rsplit('.', 1)[0] + '_debug.png'
            plt.savefig(plot_path, dpi=150)
            plt.close()
            print(f"\n  Plot saved: {plot_path}")
        except ImportError as e:
            print(f"\n  Could not generate plot (missing dependency): {e}")
        except Exception as e:
            print(f"\n  Plot error: {e}")

    return results


def main():
    parser = argparse.ArgumentParser(description='WaveDrop Audio Pipeline Debugger')
    parser.add_argument('path', help='Audio file or directory to analyze')
    parser.add_argument('--plot', action='store_true', help='Generate debug plots')
    parser.add_argument('--json', action='store_true', help='Output results as JSON')
    args = parser.parse_args()

    path = Path(args.path)
    audio_extensions = {'.wav', '.mp3', '.flac', '.m4a', '.aiff', '.ogg', '.aac'}

    if path.is_file():
        results = [analyze_file(path, plot=args.plot)]
    elif path.is_dir():
        files = sorted([f for f in path.iterdir() if f.suffix.lower() in audio_extensions])
        if not files:
            print(f"No audio files found in {path}")
            sys.exit(1)
        print(f"Found {len(files)} audio files in {path}")
        results = []
        for f in files:
            r = analyze_file(f, plot=args.plot)
            if r:
                results.append(r)
    else:
        print(f"Path not found: {path}")
        sys.exit(1)

    if args.json:
        print("\n" + json.dumps(results, indent=2))


if __name__ == '__main__':
    main()
