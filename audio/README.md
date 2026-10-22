# Mechanical sound assets

Original synthesized effects created for this project; no third-party recordings or samples.

All files are mono 16-bit PCM at 22050 Hz. The engine is a seamless one-second harmonic loop; machine, shot, impact and pickup are short synthesized tones/noise with decaying envelopes. Keep the tracked Godot import settings uncompressed so loop frame boundaries remain exact.

Runtime playback is bounded to eight effect voices and one motor, with an owned limiter bus. Settings are independent of expedition checkpoints.

Placement, connection, armor deflection, reward and combo effects are generated reproducibly by `python3 tools/generate_feedback_audio.py`. They use filtered synthetic noise and damped tones; no recorded samples. Combo playback changes pitch within a bounded range. These five sounds share the existing eight effect voices.
