package org.clarifae.mictest

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Spinner
import android.widget.ArrayAdapter
import android.widget.TextView
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class MainActivity : Activity() {
    private val sampleRate = 16000
    private val recording = AtomicBoolean(false)
    private lateinit var status: TextView
    private lateinit var toggle: Button
    private lateinit var source: Spinner
    private val sources = listOf(
        "MIC" to MediaRecorder.AudioSource.MIC,
        "VOICE_COMMUNICATION" to MediaRecorder.AudioSource.VOICE_COMMUNICATION,
        "CAMCORDER" to MediaRecorder.AudioSource.CAMCORDER,
        "VOICE_RECOGNITION" to MediaRecorder.AudioSource.VOICE_RECOGNITION
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 48, 32, 32)
            gravity = Gravity.CENTER_HORIZONTAL
        }
        layout.addView(TextView(this).apply {
            text = "Independent microphone capture test"
            textSize = 22f
        })
        layout.addView(TextView(this).apply {
            text = "Records Android AudioRecord output. Compare Clarifae OFF and ON, then repeat in a separate recording app."
            textSize = 15f
            setPadding(0, 24, 0, 24)
        })
        source = Spinner(this).apply {
            adapter = ArrayAdapter(this@MainActivity, android.R.layout.simple_spinner_dropdown_item, sources.map { it.first })
        }
        layout.addView(source)
        toggle = Button(this).apply {
            text = "Start 10-second recording"
            setOnClickListener {
                if (source.isEnabled) startCapture()
                else if (recording.get()) stopCapture()
            }
        }
        layout.addView(toggle)
        status = TextView(this).apply {
            text = "Files saved to Music/ClarifaeTest as 16 kHz mono WAV."
            setPadding(0, 24, 0, 0)
        }
        layout.addView(status)
        setContentView(layout)
    }

    private fun startCapture() {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 100)
            return
        }
        val chosen = sources[source.selectedItemPosition]
        val min = AudioRecord.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (min <= 0) { status.text = "AudioRecord unavailable"; return }
        val recorder = try {
            AudioRecord(chosen.second, sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min * 2, 4096))
        } catch (e: Exception) { status.text = "Cannot open mic: ${e.message}"; return }
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            status.text = "Mic initialization failed"
            return
        }
        recording.set(true)
        toggle.text = "Stop and save"
        source.isEnabled = false
        status.text = "Recording ${chosen.first}…"
        thread(name = "clarifae-independent-capture") {
            val pcm = ByteArrayOutputStream()
            val buffer = ByteArray(4096)
            var error: String? = null
            try {
                recorder.startRecording()
                check(recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) { "Microphone did not start" }
                val captureBytes = sampleRate * 2 * 10
                val deadline = System.nanoTime() + 15_000_000_000L
                while (recording.get() && pcm.size() < captureBytes && System.nanoTime() < deadline) {
                    val n = recorder.read(buffer, 0, minOf(buffer.size, captureBytes - pcm.size()))
                    if (n > 0) pcm.write(buffer, 0, n)
                    else if (n < 0) { error = "AudioRecord read error: $n"; break }
                }
            } catch (e: Exception) {
                error = e.message ?: "Capture failed"
            } finally {
                recording.set(false)
                try { recorder.stop() } catch (_: Exception) {}
                recorder.release()
                val outcome = if (error != null) error else if (pcm.size() == 0) "No audio captured"
                    else try { saveWav(pcm.toByteArray(), chosen.first) } catch (e: Exception) { "Save failed: ${e.message}" }
                runOnUiThread {
                    toggle.text = "Start 10-second recording"
                    toggle.isEnabled = true
                    source.isEnabled = true
                    status.text = outcome
                }
            }
        }
    }

    private fun stopCapture() {
        recording.set(false)
        toggle.isEnabled = false
    }

    private fun saveWav(pcm: ByteArray, label: String): String {
        val filename = "clarifae_${label}_${System.currentTimeMillis()}.wav"
        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, filename)
            put(MediaStore.Audio.Media.MIME_TYPE, "audio/wav")
            put(MediaStore.Audio.Media.RELATIVE_PATH, Environment.DIRECTORY_MUSIC + "/ClarifaeTest")
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val uri = contentResolver.insert(collection, values) ?: error("MediaStore insert failed")
        try {
            contentResolver.openOutputStream(uri)?.use { stream ->
                val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
                header.put("RIFF".toByteArray(Charsets.US_ASCII))
                header.putInt(36 + pcm.size)
                header.put("WAVEfmt ".toByteArray(Charsets.US_ASCII))
                header.putInt(16)
                header.putShort(1.toShort())
                header.putShort(1.toShort())
                header.putInt(sampleRate)
                header.putInt(sampleRate * 2)
                header.putShort(2.toShort())
                header.putShort(16.toShort())
                header.put("data".toByteArray(Charsets.US_ASCII))
                header.putInt(pcm.size)
                stream.write(header.array())
                stream.write(pcm)
            } ?: error("Cannot open output stream")
            contentResolver.update(uri, ContentValues().apply { put(MediaStore.Audio.Media.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            throw e
        }
        return "Saved $filename — compare with module OFF/ON and a separate app."
    }

    override fun onStop() {
        if (recording.get()) stopCapture()
        super.onStop()
    }
}
