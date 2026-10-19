// Makes a web recording playable on every device (iPhone, Android, every
// browser). Browsers record different formats: Safari and usually Chrome
// record AAC, which plays everywhere; Firefox (and Chrome when its AAC
// recorder fails) record Opus, which iPhones can't play. Those are converted
// here: to AAC (.m4a) with the browser's own encoder (WebCodecs) when it has
// one, otherwise (Firefox) to WAV, which every device plays and needs no
// third-party encoder.
//
// Runs in the Flutter web page (not the editor iframe), loaded by the package
// as assets/web_audio/audio.js.
import { ArrayBufferTarget, Muxer } from 'mp4-muxer';

// Formats that already play everywhere.
const PLAYABLE = ['audio/mp4', 'audio/x-m4a', 'audio/aac', 'audio/mpeg', 'audio/wav', 'audio/x-wav', 'audio/wave'];

const AAC_RATE = 44100;
const AAC_BITRATE = 64000;
// Speech: 16 kHz mono is clear (about 1.9 MB per minute as WAV).
const WAV_RATE = 16000;

/** The recording decoded to mono samples at [sampleRate]. */
async function decode(blob, sampleRate) {
  // An OfflineAudioContext decodes and resamples without touching the speakers.
  const buffer = await new OfflineAudioContext(1, 1, sampleRate).decodeAudioData(await blob.arrayBuffer());
  if (buffer.numberOfChannels === 1) return buffer.getChannelData(0);
  const mono = new Float32Array(buffer.length);
  for (let c = 0; c < buffer.numberOfChannels; c++) {
    const channel = buffer.getChannelData(c);
    for (let i = 0; i < mono.length; i++) mono[i] += channel[i] / buffer.numberOfChannels;
  }
  return mono;
}

/** AAC in an .m4a, or null if this browser can't encode AAC. */
async function toAac(blob) {
  const config = { codec: 'mp4a.40.2', sampleRate: AAC_RATE, numberOfChannels: 1, bitrate: AAC_BITRATE };
  if (typeof AudioEncoder === 'undefined') return null;
  if (!(await AudioEncoder.isConfigSupported(config).catch(() => ({ supported: false }))).supported) return null;

  const samples = await decode(blob, AAC_RATE);
  const muxer = new Muxer({
    target: new ArrayBufferTarget(),
    audio: { codec: 'aac', numberOfChannels: 1, sampleRate: AAC_RATE },
    fastStart: 'in-memory',
  });
  let failure = null;
  const encoder = new AudioEncoder({
    output: (chunk, meta) => muxer.addAudioChunk(chunk, meta),
    error: (error) => (failure = error),
  });
  encoder.configure(config);
  const frame = 4096;
  for (let i = 0; i < samples.length && !failure; i += frame) {
    const data = samples.slice(i, i + frame);
    encoder.encode(
      new AudioData({
        format: 'f32',
        sampleRate: AAC_RATE,
        numberOfChannels: 1,
        numberOfFrames: data.length,
        timestamp: Math.round((i / AAC_RATE) * 1e6),
        data,
      }),
    );
    // Don't queue the whole recording at once.
    if (encoder.encodeQueueSize > 32) await new Promise((resolve) => encoder.addEventListener('dequeue', resolve, { once: true }));
  }
  await encoder.flush();
  encoder.close();
  if (failure) throw failure;
  muxer.finalize();
  return new Blob([muxer.target.buffer], { type: 'audio/mp4' });
}

/** 16-bit PCM WAV: plays everywhere, and any browser can make it. */
async function toWav(blob) {
  const samples = await decode(blob, WAV_RATE);
  const data = new DataView(new ArrayBuffer(44 + samples.length * 2));
  const ascii = (offset, text) => [...text].forEach((c, i) => data.setUint8(offset + i, c.charCodeAt(0)));
  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, true);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, true); // format chunk size
  data.setUint16(20, 1, true); // PCM
  data.setUint16(22, 1, true); // mono
  data.setUint32(24, WAV_RATE, true);
  data.setUint32(28, WAV_RATE * 2, true); // bytes per second
  data.setUint16(32, 2, true); // bytes per sample
  data.setUint16(34, 16, true); // bits per sample
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, true);
  for (let i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, Math.max(-1, Math.min(1, samples[i])) * 0x7fff, true);
  }
  return new Blob([data.buffer], { type: 'audio/wav' });
}

window.aminotesAudio = {
  /**
   * Returns {url, type, converted}: [url] itself when it already plays
   * everywhere, otherwise a new blob: URL with AAC (or WAV), and [url] is
   * revoked. Options (tests):
   * {force: true} converts even playable audio; {fallback: true} skips AAC.
   */
  async toPlayable(url, options = {}) {
    const blob = await (await fetch(url)).blob();
    if (!options.force && PLAYABLE.some((type) => blob.type.startsWith(type))) {
      return { url, type: blob.type, converted: false };
    }
    let out = null;
    if (!options.fallback) {
      try {
        out = await toAac(blob);
      } catch (error) {
        console.warn('aminotes: AAC encoding failed, using WAV', error);
      }
    }
    out ??= await toWav(blob);
    // The original recording isn't used any more: free its memory.
    URL.revokeObjectURL(url);
    return { url: URL.createObjectURL(out), type: out.type, converted: true };
  },
};
