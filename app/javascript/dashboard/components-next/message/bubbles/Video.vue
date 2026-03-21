<script setup>
import { ref, computed } from 'vue';
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { ATTACHMENT_TYPES } from '../constants';

const emit = defineEmits(['error']);
const hasError = ref(false);
const showGallery = ref(false);
const { filteredCurrentChatAttachments, attachments, status, progressPercentage } = useMessageContext();

const isUploading = computed(() => {
  return status?.value === 'progress' && progressPercentage?.value > 0 && progressPercentage?.value < 100;
});

const handleError = () => {
  hasError.value = true;
  emit('error');
};

const attachment = computed(() => {
  return attachments.value[0];
});

const isReel = computed(() => {
  return attachment.value.fileType === ATTACHMENT_TYPES.IG_REEL;
});
</script>

<template>
  <BaseBubble
    class="overflow-hidden p-3"
    data-bubble-name="video"
    @click="showGallery = true"
  >
    <div class="relative group rounded-lg overflow-hidden">
      <div
        v-if="isReel"
        class="absolute p-2 flex items-start justify-end right-0 pointer-events-none"
      >
        <Icon icon="i-lucide-instagram" class="text-white shadow-lg" />
      </div>
      <video
        controls
        class="rounded-lg skip-context-menu"
        :src="attachment.dataUrl"
        :class="{
          'max-w-48': isReel,
          'max-w-full': !isReel,
        }"
        @click.stop
        @error="handleError"
      />
      <div
        v-if="isUploading"
        class="absolute inset-x-2 bottom-2.5 bg-black/40 rounded-full overflow-hidden h-1.5 z-20"
      >
        <div
          class="h-full bg-white transition-all duration-300 ease-out"
          :style="{ width: `${progressPercentage}%` }"
        ></div>
      </div>
    </div>
  </BaseBubble>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(attachment)"
    :all-attachments="filteredCurrentChatAttachments"
    @error="onError"
    @close="() => (showGallery = false)"
  />
</template>
