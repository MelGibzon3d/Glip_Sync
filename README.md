# Godot Rhubarb Lip Sync Baker - User Guide

This custom `LipSyncBaker` tool allows you to instantly  map audio files into perfectly timed mouth animations natively inside Godot 4, either by parsing pre-generated Rhubarb files or by letting Godot automatically run Rhubarb in the background!

---

## 🚀 Quick Start (Auto-Generation)

The easiest way to use the baker is to let it automatically run `rhubarb.exe` under the hood.

1. **Clear the Rhubarb File Box:** Ensure the top box (`Rhubarb File`) is completely empty (click the revert/curly-arrow icon so it shows blank or `<null>`).
2. **Assign the Executable:** Under `Rhubarb Auto-Generation`, point the `Rhubarb Executable Path` to your downloaded `rhubarb.exe` file (must be inside a folder that also contains its `res` folder!).
3. **Assign Target Nodes:** 
   - `Mesh Node`: The character model with the facial blend shapes.
   - `Audio Player Node`: The AudioStreamPlayer that will play the voice line.
   - `Audio Stream`: Your `.wav` or `.ogg` dialogue file!
   - `Animation Player Node`: Where the animation will be saved.
4. **Bake:** Set an `Animation Name` (e.g. "IntroSpeech") and click the **Bake Now** checkbox! 
5. **Done!** The script will silently convert your audio, build an Animation, add all the shape-key data, inject an Audio track perfectly timed to `0.0s`, and save it straight to your AnimationPlayer!

---

## ⚙️ Inspector Settings Breakdown

### 1. Manual Override
* **Rhubarb File:** If you provide a `.txt` or `.json` file here, the script will **ignore the auto-generation process** entirely and bake the animation using the file you provided. Great for manual edits!

### 2. Rhubarb Auto-Generation
* **Rhubarb Executable Path:** Points to `rhubarb.exe` on your machine.
* **Recognizer:** 
  * `POCKET_SPHINX`: Uses an English phonetic dictionary. Highly accurate for standard English speech.
  * `PHONETIC`: Language-agnostic. Analyzes raw sound instead of English words. Great for gibberish, monstrous sounds, or non-English languages.
* **Rhubarb Save Directory:** (Optional) If you want the script to save the `.json` file to your project for backup or manual editing later, assign a folder here. If left empty, it runs entirely in temporary memory!

### 3. Viseme Mapping
* Rhubarb spits out 8 mouth shapes (`A` through `H`) and a resting shape (`X`). 
* Here you simply type the exact name of the blend shape on your mesh that matches the sound!
* *Tip:* To shut the mouth completely, make sure `Map X` and `Map A` both point to your fully closed mouth shape (like "Mouth_Closed").
* *Tip:* If your model doesn't have enough shapes for `G` and `H`, just assign them to the closest open-mouth shape, or leave them totally blank to default to silence.

#### Rhubarb Phonetic Reference (For 3D Modelers)
Use this reference when sculpting your blend shapes in Blender or Maya to ensure they line up perfectly with Rhubarb's outputs:
- **A (Closed Mouth)** — Used for **M, B, P** consonants. Lips are firmly pressed together.
- **B (Slightly Open)** — Used for **K, S, T** consonants. Teeth are close, mouth is barely open.
- **C (Open Mouth)** — Used for **Aa, Eh** vowels. A standard, relaxed open mouth.
- **D (Wide Open)** — Used for **Ah** sounds. The jaw drops lower than C.
- **E (Slightly Rounded)** — Used for **O, Oo** sounds. Lips are slightly pursed/rounded.
- **F (Puckered Lips)** — Used for **W, Q, R** consonants. Lips are tightly pursed together.
- **G (Upper Teeth Visible)** — Used for **F, V** consonants. Bottom lip tucked under upper teeth.
- **H (Very Wide Open - Optional)** — Used for **L, Th** consonants. Can usually just safely reuse the `C` or `D` shape if you don't want to model it.
- **X (Silence / Rest)** — Background noise or silence. The mouth should be in its default closed, resting posture.

### 4. Blending & Smoothness
* **Blend Mode (`BY_RATIO` vs `FIXED_TIME`):**
  * **By Ratio:** Perfectly mimics the Blender NLA algorithm. It creates a smooth, constantly blending "triangle wave" that reaches its maximum shape at exactly the middle of the syllable. Smooth, floaty, natural. Adjust the **Blend Ratio** slider lower (`0.1`) if you want it snappier, or higher (`0.5`) for maximum drift.
  * **Fixed Time:** Creates sturdy "Plateaus". The mouth will snap open perfectly in X seconds, strictly lock onto the shape for the duration of the syllable, and cleanly drop out. Highly recommended for snappy, anime-style, or heavily stylized game animations! Adjust **Fixed Blend Time** to control the snap speed (e.g., `0.07` for fast snaps).
