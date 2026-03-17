<script setup>
import getUuid from 'widget/helpers/uuid';
import { ref, onMounted, onUnmounted, defineEmits, defineExpose } from 'vue';
import WaveSurfer from 'wavesurfer.js';
import RecordPlugin from 'wavesurfer.js/dist/plugins/record.js';
import { format, intervalToDuration } from 'date-fns';
import { convertAudio } from './utils/mp3ConversionUtils';

const props = defineProps({
  audioRecordFormat: {
    type: String,
    required: true,
  },
});

const emit = defineEmits([
  'recorderProgressChanged',
  'finishRecord',
  'pause',
  'play',
]);

const waveformContainer = ref(null);
const wavesurfer = ref(null);
const record = ref(null);
const isRecording = ref(false);
const isPlaying = ref(false);
const hasRecording = ref(false);

const formatTimeProgress = time => {
  const duration = intervalToDuration({ start: 0, end: time });
  return format(
    new Date(0, 0, 0, 0, duration.minutes, duration.seconds),
    'mm:ss'
  );
};

const initWaveSurfer = () => {
  wavesurfer.value = WaveSurfer.create({
    container: waveformContainer.value,
    waveColor: '#1F93FF',
    progressColor: '#6E6F73',
    height: 100,
    barWidth: 2,
    barGap: 1,
    barRadius: 2,
    plugins: [
      RecordPlugin.create({
        scrollingWaveform: true,
        renderRecordedAudio: false,
      }),
    ],
  });

  wavesurfer.value.on('pause', () => emit('pause'));
  wavesurfer.value.on('play', () => emit('play'));

  record.value = wavesurfer.value.plugins[0];

  wavesurfer.value.on('finish', () => {
    isPlaying.value = false;
  });

  record.value.on('record-end', async blob => {
    const audioUrl = URL.createObjectURL(blob);
    let audioBlob = blob;
    let outputType = blob.type || props.audioRecordFormat;

    try {
      audioBlob = await convertAudio(blob, props.audioRecordFormat);
      outputType = props.audioRecordFormat;
    } catch (error) {
      // If conversion fails in the browser, fall back to the original recording blob.
      audioBlob = blob;
      outputType = blob.type || props.audioRecordFormat;
    }

    const ext =
      outputType === 'audio/wav'
        ? 'wav'
        : outputType === 'audio/mp3'
          ? 'mp3'
          : outputType === 'audio/mpeg'
            ? 'mp3'
            : outputType.includes('webm')
              ? 'webm'
              : outputType.includes('ogg')
                ? 'ogg'
                : 'audio';

    const fileName = `${getUuid()}.${ext}`;
    const file = new File([audioBlob], fileName, { type: outputType });
    wavesurfer.value.load(audioUrl);
    emit('finishRecord', {
      name: file.name,
      type: file.type,
      size: file.size,
      file,
    });
    hasRecording.value = true;
    isRecording.value = false;
  });

  record.value.on('record-progress', time => {
    emit('recorderProgressChanged', formatTimeProgress(time));
  });
};

const stopRecording = () => {
  if (isRecording.value) {
    record.value.stopRecording();
    isRecording.value = false;
  }
};

const startRecording = () => {
  record.value.startRecording();
  isRecording.value = true;
};

const playPause = () => {
  if (hasRecording.value) {
    wavesurfer.value.playPause();
    isPlaying.value = !isPlaying.value;
  }
};

onMounted(() => {
  initWaveSurfer();
  startRecording();
});

onUnmounted(() => {
  if (wavesurfer.value) {
    wavesurfer.value.destroy();
  }
});

defineExpose({ playPause, stopRecording, record });
</script>

<template>
  <div ref="waveformContainer" class="w-full p-1" />
</template>
