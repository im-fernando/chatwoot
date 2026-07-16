<script setup>
import {
  computed,
  onMounted,
  onBeforeUnmount,
  useTemplateRef,
  ref,
  getCurrentInstance,
} from 'vue';
import Icon from 'next/icon/Icon.vue';
import { timeStampAppendedURL } from 'dashboard/helper/URLHelper';
import { downloadFile } from '@chatwoot/utils';
import { useEmitter } from 'dashboard/composables/emitter';
import { emitter } from 'shared/helpers/mitt';

const { attachment } = defineProps({
  attachment: {
    type: Object,
    required: true,
  },
  showTranscribedText: {
    type: Boolean,
    default: true,
  },
});

defineOptions({
  inheritAttrs: false,
});

const timeStampURL = computed(() => {
  return timeStampAppendedURL(attachment.dataUrl);
});

const TRANSCRIPT_PREVIEW_LENGTH = 200;
const isTranscriptExpanded = ref(false);
const isTranscriptLong = computed(
  () => (attachment.transcribedText?.length || 0) > TRANSCRIPT_PREVIEW_LENGTH
);
const displayedTranscript = computed(() => {
  const text = attachment.transcribedText || '';
  if (!isTranscriptLong.value || isTranscriptExpanded.value) return text;
  return `${text.slice(0, TRANSCRIPT_PREVIEW_LENGTH).trimEnd()}…`;
});

const audioPlayer = useTemplateRef('audioPlayer');

const isPlaying = ref(false);
const isMuted = ref(false);
const currentTime = ref(0);
const duration = ref(0);
const playbackSpeed = ref(1);
const isProbingDuration = ref(false);
const loadAttempts = ref(0);
const MAX_LOAD_ATTEMPTS = 3;
let reloadTimer = null;
let watchdogTimer = null;

const clearTimers = () => {
  if (reloadTimer) {
    clearTimeout(reloadTimer);
    reloadTimer = null;
  }
  if (watchdogTimer) {
    clearTimeout(watchdogTimer);
    watchdogTimer = null;
  }
};

// Race seen in agent-to-agent flow: ActionCable broadcasts MESSAGE_CREATED
// before the attachment is fully available on the storage backend, so the
// audio element's first fetch comes back empty/partial and gets stuck at
// 0:00 with no automatic retry. Calling load() again after a delay forces
// a fresh fetch once the file is actually there.
const scheduleReload = () => {
  if (loadAttempts.value >= MAX_LOAD_ATTEMPTS) return;
  if (reloadTimer) return;
  loadAttempts.value += 1;
  const delay = 1500 * loadAttempts.value;
  reloadTimer = setTimeout(() => {
    reloadTimer = null;
    if (audioPlayer.value) audioPlayer.value.load();
  }, delay);
};

const { uid } = getCurrentInstance();

const applyDurationFromPlayer = () => {
  const value = audioPlayer.value?.duration;
  if (Number.isFinite(value) && value > 0) {
    duration.value = value;
    return true;
  }
  return false;
};

// WhatsApp voice notes (Ogg/Opus/WebM) often arrive without a duration in the
// container, so the browser reports Infinity until the full file is fetched —
// that's the "stuck at 0:00 for ~1 minute" case. Seeking past the end forces
// the browser to scan the stream and expose the real duration.
const probeDuration = () => {
  if (isProbingDuration.value || !audioPlayer.value) return;
  isProbingDuration.value = true;
  const onProbeTimeUpdate = () => {
    audioPlayer.value.removeEventListener('timeupdate', onProbeTimeUpdate);
    try {
      audioPlayer.value.currentTime = 0;
    } catch {
      /* ignore seek errors */
    }
    applyDurationFromPlayer();
    isProbingDuration.value = false;
  };
  audioPlayer.value.addEventListener('timeupdate', onProbeTimeUpdate);
  try {
    audioPlayer.value.currentTime = 1e101;
  } catch {
    audioPlayer.value.removeEventListener('timeupdate', onProbeTimeUpdate);
    isProbingDuration.value = false;
  }
};

const armWatchdog = () => {
  if (watchdogTimer) clearTimeout(watchdogTimer);
  watchdogTimer = setTimeout(() => {
    watchdogTimer = null;
    if (duration.value > 0) return;
    scheduleReload();
  }, 2500);
};

const onLoadedMetadata = () => {
  if (applyDurationFromPlayer()) {
    loadAttempts.value = 0;
    return;
  }
  probeDuration();
  armWatchdog();
};

const onDurationChange = () => {
  if (isProbingDuration.value) return;
  if (applyDurationFromPlayer()) {
    loadAttempts.value = 0;
  }
};

const onMediaError = () => {
  scheduleReload();
};

const playbackSpeedLabel = computed(() => {
  return `${playbackSpeed.value}x`;
});

// There maybe a chance that the audioPlayer ref is not available
// When the onLoadMetadata is called, so we need to set the duration
// value when the component is mounted
onMounted(() => {
  applyDurationFromPlayer();
  audioPlayer.value.playbackRate = playbackSpeed.value;
  armWatchdog();
});

onBeforeUnmount(() => {
  clearTimers();
});

// Listen for global audio play events and pause if it's not this audio
useEmitter('pause_playing_audio', currentPlayingId => {
  if (currentPlayingId !== uid && isPlaying.value) {
    try {
      audioPlayer.value.pause();
    } catch {
      /* ignore pause errors */
    }
    isPlaying.value = false;
  }
});

const formatTime = time => {
  if (!time || Number.isNaN(time)) return '00:00';
  const minutes = Math.floor(time / 60);
  const seconds = Math.floor(time % 60);
  return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
};

const toggleMute = () => {
  audioPlayer.value.muted = !audioPlayer.value.muted;
  isMuted.value = audioPlayer.value.muted;
};

const onTimeUpdate = () => {
  if (isProbingDuration.value) return;
  currentTime.value = audioPlayer.value?.currentTime;
};

const seek = event => {
  const time = Number(event.target.value);
  audioPlayer.value.currentTime = time;
  currentTime.value = time;
};

const playOrPause = () => {
  if (isPlaying.value) {
    audioPlayer.value.pause();
    isPlaying.value = false;
  } else {
    // Emit event to pause all other audio
    emitter.emit('pause_playing_audio', uid);
    audioPlayer.value.play();
    isPlaying.value = true;
  }
};

const onEnd = () => {
  isPlaying.value = false;
  currentTime.value = 0;
  playbackSpeed.value = 1;
  audioPlayer.value.playbackRate = 1;
};

const changePlaybackSpeed = () => {
  const speeds = [1, 1.5, 2];
  const currentIndex = speeds.indexOf(playbackSpeed.value);
  const nextIndex = (currentIndex + 1) % speeds.length;
  playbackSpeed.value = speeds[nextIndex];
  audioPlayer.value.playbackRate = playbackSpeed.value;
};

const downloadAudio = async () => {
  const { fileType, dataUrl, extension } = attachment;
  downloadFile({ url: dataUrl, type: fileType, extension });
};
</script>

<template>
  <audio
    ref="audioPlayer"
    controls
    preload="metadata"
    class="hidden"
    playsinline
    @loadedmetadata="onLoadedMetadata"
    @durationchange="onDurationChange"
    @timeupdate="onTimeUpdate"
    @ended="onEnd"
    @error="onMediaError"
  >
    <source :src="timeStampURL" />
  </audio>
  <div
    v-bind="$attrs"
    class="rounded-xl w-full gap-2 p-1.5 bg-n-alpha-white flex flex-col items-center border border-n-container shadow-[0px_2px_8px_0px_rgba(94,94,94,0.06)]"
  >
    <div class="flex gap-1 w-full flex-1 items-center justify-start">
      <button class="p-0 border-0 size-8" @click="playOrPause">
        <Icon
          v-if="isPlaying"
          class="size-8"
          icon="i-teenyicons-pause-small-solid"
        />
        <Icon v-else class="size-8" icon="i-teenyicons-play-small-solid" />
      </button>
      <div class="tabular-nums text-xs">
        {{ formatTime(currentTime) }} / {{ formatTime(duration) }}
      </div>
      <div class="flex-1 items-center flex px-2">
        <input
          type="range"
          min="0"
          :max="duration"
          :value="currentTime"
          class="w-full h-1 bg-n-slate-12/40 rounded-lg appearance-none cursor-pointer accent-current"
          @input="seek"
        />
      </div>
      <button
        class="border-0 w-10 h-6 grid place-content-center bg-n-alpha-2 hover:bg-alpha-3 rounded-2xl"
        @click="changePlaybackSpeed"
      >
        <span class="text-xs text-n-slate-11 font-medium">
          {{ playbackSpeedLabel }}
        </span>
      </button>
      <button
        class="p-0 border-0 size-8 grid place-content-center"
        @click="toggleMute"
      >
        <Icon v-if="isMuted" class="size-4" icon="i-lucide-volume-off" />
        <Icon v-else class="size-4" icon="i-lucide-volume-2" />
      </button>
      <button
        class="p-0 border-0 size-8 grid place-content-center"
        @click="downloadAudio"
      >
        <Icon class="size-4" icon="i-lucide-download" />
      </button>
    </div>

    <div
      v-if="attachment.transcribedText && showTranscribedText"
      class="text-n-slate-12 p-3 text-sm bg-n-alpha-1 rounded-lg w-full break-words"
    >
      {{ displayedTranscript }}
      <button
        v-if="isTranscriptLong"
        class="block mt-1 p-0 border-0 bg-transparent text-n-slate-11 hover:text-n-slate-12 font-medium"
        @click="isTranscriptExpanded = !isTranscriptExpanded"
      >
        {{
          isTranscriptExpanded
            ? $t('CONVERSATION.VOICE_CALL.TRANSCRIPT_SHOW_LESS')
            : $t('CONVERSATION.VOICE_CALL.TRANSCRIPT_SHOW_MORE')
        }}
      </button>
    </div>
  </div>
</template>
