<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatBytes } from 'shared/helpers/FileHelper';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  attachments: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['removeAttachment']);

const { t } = useI18n();

const nonRecordedAudioAttachments = computed(() => {
  return props.attachments.filter(attachment => !attachment?.isVoiceMessage);
});

const recordedAudioAttachments = computed(() =>
  props.attachments.filter(attachment => attachment.isVoiceMessage)
);

const uploadingCount = computed(() =>
  props.attachments.filter(a => a.isUploading).length
);

const totalCount = computed(() => props.attachments.length);

const uploadedCount = computed(
  () => totalCount.value - uploadingCount.value
);

const isUploading = computed(() => uploadingCount.value > 0);

const onRemoveAttachment = itemIndex => {
  emit(
    'removeAttachment',
    nonRecordedAudioAttachments.value
      .filter((_, index) => index !== itemIndex)
      .concat(recordedAudioAttachments.value)
  );
};

const formatFileSize = file => {
  const size = file.byte_size || file.size;
  return formatBytes(size, 0);
};

const isTypeImage = file => {
  const type = file.content_type || file.type;
  return type.includes('image');
};

const fileName = file => {
  return file.filename || file.name;
};
</script>

<template>
  <div>
    <div
      v-if="isUploading"
      class="flex items-center gap-1.5 px-2 py-1 mb-1 text-xs font-medium rounded-md bg-woot-25 dark:bg-woot-800/20 text-woot-600 dark:text-woot-300"
    >
      <span class="i-lucide-loader-circle animate-spin text-sm" />
      <span>
        {{ t('CONVERSATION.UPLOADING_ATTACHMENTS', { uploaded: uploadedCount, total: totalCount }) }}
      </span>
    </div>
    <div class="flex flex-wrap gap-y-1 gap-x-2 overflow-auto max-h-[12.5rem]">
      <div
        v-for="(attachment, index) in nonRecordedAudioAttachments"
        :key="attachment.id"
        class="flex items-center p-1 bg-n-slate-3 gap-1 rounded-md w-[15rem] relative overflow-hidden"
      >
        <div class="max-w-[4rem] flex-shrink-0 w-6 flex items-center z-10">
          <img
            v-if="isTypeImage(attachment.resource)"
            class="object-cover w-6 h-6 rounded-sm transition-opacity duration-300"
            :class="attachment.isUploading ? 'opacity-50 grayscale' : 'opacity-100'"
            :src="attachment.thumb"
          />
          <span v-else class="relative w-6 h-6 text-lg text-left -top-px" :class="attachment.isUploading ? 'opacity-50' : ''">
            📄
          </span>
        </div>
        <div class="max-w-3/5 min-w-[50%] overflow-hidden text-ellipsis z-10">
          <span
            class="h-4 overflow-hidden text-sm font-medium text-ellipsis whitespace-nowrap"
          >
            {{ fileName(attachment.resource) }}
          </span>
        </div>
        <div class="w-[30%] justify-center z-10">
          <span class="overflow-hidden text-xs text-ellipsis whitespace-nowrap" :class="attachment.isUploading ? 'text-woot-500 font-semibold' : ''">
            <template v-if="attachment.isUploading">
              {{ attachment.progress || 0 }}%
            </template>
            <template v-else>
              {{ formatFileSize(attachment.resource) }}
            </template>
          </span>
        </div>
        <div class="flex items-center justify-center z-10">
          <Button
            ghost
            slate
            xs
            icon="i-lucide-x"
            @click="onRemoveAttachment(index)"
          />
        </div>
        <div
          v-if="attachment.isUploading"
          class="absolute bottom-0 left-0 h-1 bg-woot-500 transition-all duration-300 ease-out z-0"
          :style="{ width: `${attachment.progress || 0}%` }"
        />
      </div>
    </div>
  </div>
</template>
