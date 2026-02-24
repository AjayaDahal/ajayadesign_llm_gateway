"""
MusicGen Playground — Gradio Web UI
A simple browser interface for the MusicGen text-to-music API.
Connects to the MusicGen FastAPI backend at MUSICGEN_API_URL.
"""

import os
import io
import time
import tempfile
import requests
import gradio as gr

MUSICGEN_API_URL = os.environ.get("MUSICGEN_API_URL", "http://localhost:8003")

# ── Preset prompts for quick demos ──
PRESETS = {
    "🎸 Epic Rock": "epic rock guitar riff with heavy drums and powerful bass, energetic and intense",
    "🎹 Chill Lo-fi": "lo-fi hip hop beat with soft piano, vinyl crackle, relaxing and mellow",
    "🎵 Cinematic": "cinematic orchestral soundtrack, epic and emotional, sweeping strings and brass",
    "🎶 Jazz Café": "smooth jazz piano trio, upright bass, brushed drums, warm cafe atmosphere",
    "🎧 EDM Drop": "electronic dance music with heavy bass drop, synth leads, festival energy",
    "🎻 Classical": "classical string quartet, elegant and refined, baroque style composition",
    "🌊 Ambient": "ambient atmospheric soundscape, ethereal pads, nature sounds, meditative",
    "🎺 Funk": "funky bass groove with brass section, tight drums, 70s disco vibes",
    "🎤 Hip Hop": "booming 808 trap beat with dark synths, hard-hitting drums, aggressive",
    "🌴 Reggae": "reggae rhythm with offbeat guitar, warm bass, laid-back island vibes",
}


def check_health():
    """Check if MusicGen API is healthy."""
    try:
        r = requests.get(f"{MUSICGEN_API_URL}/health", timeout=5)
        data = r.json()
        if data.get("model_loaded"):
            return f"✅ Connected — {data['model']} loaded on {data['device']}"
        return f"⏳ Model loading..."
    except Exception as e:
        return f"❌ API unreachable: {e}"


def generate_music(prompt, duration, temperature, top_k):
    """Call MusicGen API and return audio file path."""
    if not prompt or not prompt.strip():
        raise gr.Error("Please enter a music description!")

    try:
        start = time.time()
        response = requests.post(
            f"{MUSICGEN_API_URL}/generate",
            json={
                "prompt": prompt.strip(),
                "duration": float(duration),
                "temperature": float(temperature),
                "top_k": int(top_k),
            },
            timeout=300,  # MusicGen can be slow on CPU
        )

        if response.status_code != 200:
            error = response.json().get("detail", response.text)
            raise gr.Error(f"Generation failed: {error}")

        elapsed = time.time() - start
        gen_time = response.headers.get("X-Generation-Time", f"{elapsed:.1f}")
        audio_dur = response.headers.get("X-Duration-Seconds", str(duration))

        # Save to temp file for Gradio
        tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        tmp.write(response.content)
        tmp.close()

        status = f"✅ Generated {audio_dur}s of audio in {gen_time}s ({len(response.content)/1024:.0f} KB)"
        return tmp.name, status

    except requests.exceptions.Timeout:
        raise gr.Error("Generation timed out — try a shorter duration")
    except requests.exceptions.ConnectionError:
        raise gr.Error(f"Cannot connect to MusicGen API at {MUSICGEN_API_URL}")


def load_preset(preset_name):
    """Load a preset prompt."""
    return PRESETS.get(preset_name, "")


# ── Build the Gradio UI ──
with gr.Blocks(
    title="🎵 MusicGen Playground",
    theme=gr.themes.Soft(primary_hue="violet"),
    css="""
    .main-title { text-align: center; margin-bottom: 0.5em; }
    .subtitle { text-align: center; color: #666; margin-bottom: 1.5em; }
    """,
) as app:

    gr.HTML("<h1 class='main-title'>🎵 MusicGen Playground</h1>")
    gr.HTML("<p class='subtitle'>Generate music from text descriptions — Powered by Meta AudioCraft</p>")

    with gr.Row():
        health_status = gr.Textbox(
            label="API Status",
            value=check_health(),
            interactive=False,
            scale=3,
        )
        refresh_btn = gr.Button("🔄 Refresh", scale=1)
        refresh_btn.click(check_health, outputs=health_status)

    with gr.Row():
        with gr.Column(scale=2):
            prompt = gr.Textbox(
                label="🎼 Music Description",
                placeholder="Describe the music you want to generate...\nE.g.: upbeat electronic dance music with heavy bass and synth melodies",
                lines=3,
            )

            with gr.Row():
                preset_dropdown = gr.Dropdown(
                    choices=list(PRESETS.keys()),
                    label="Quick Presets",
                    scale=3,
                )
                load_btn = gr.Button("Load Preset", scale=1)
                load_btn.click(load_preset, inputs=preset_dropdown, outputs=prompt)

            with gr.Row():
                duration = gr.Slider(
                    minimum=1, maximum=30, value=8, step=1,
                    label="⏱️ Duration (seconds)",
                    info="Longer = slower generation (especially on CPU)",
                )
                temperature = gr.Slider(
                    minimum=0.1, maximum=2.0, value=1.0, step=0.1,
                    label="🌡️ Temperature",
                    info="Higher = more creative/random",
                )
                top_k = gr.Slider(
                    minimum=1, maximum=1000, value=250, step=10,
                    label="🎯 Top-K",
                    info="Lower = more focused",
                )

            generate_btn = gr.Button("🎵 Generate Music", variant="primary", size="lg")

        with gr.Column(scale=2):
            audio_output = gr.Audio(
                label="🔊 Generated Music",
                type="filepath",
            )
            gen_status = gr.Textbox(
                label="Generation Info",
                interactive=False,
            )

    generate_btn.click(
        generate_music,
        inputs=[prompt, duration, temperature, top_k],
        outputs=[audio_output, gen_status],
    )

    gr.HTML("""
    <details style="margin-top: 1em; color: #888;">
        <summary>Tips for better results</summary>
        <ul>
            <li>Be descriptive: mention instruments, mood, tempo, genre</li>
            <li>Specify style: "80s synthwave", "baroque classical", "trap beat"</li>
            <li>Add atmosphere: "warm", "energetic", "melancholic", "dreamy"</li>
            <li>Duration: 5-10s for quick tests, 20-30s for full clips</li>
            <li>Temperature: 0.8-1.0 for balanced, 1.5+ for experimental</li>
        </ul>
    </details>
    """)


if __name__ == "__main__":
    app.launch(server_name="0.0.0.0", server_port=7860)
