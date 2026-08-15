<script setup>
import { computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useMessageContext } from '../provider.js';

/**
 * Options offered by an incoming WhatsApp interactive message (buttons, list or template).
 * Picking one replies with that exact text, quoting the prompt and flagged as an interactive
 * reply so it goes out unsigned — the same thing the customer tapping the button would send.
 */
const { id, conversationId, contentAttributes } = useMessageContext();
const store = useStore();

const options = computed(
  () => contentAttributes.value?.interactiveOptions ?? []
);

const selectOption = option => {
  if (option.url) {
    window.open(option.url, '_blank', 'noopener');
    return;
  }

  store.dispatch('createPendingMessageAndSend', {
    conversationId: conversationId.value,
    message: option.title,
    private: false,
    contentAttributes: {
      in_reply_to: id.value,
      interactive_reply: true,
    },
  });
};
</script>

<template>
  <div class="flex flex-wrap gap-2">
    <button
      v-for="option in options"
      :key="option.title"
      type="button"
      class="px-3 py-1.5 text-sm rounded-lg border border-n-strong text-n-slate-12 hover:bg-n-slate-3 max-w-full truncate"
      :title="option.url || option.title"
      @click="selectOption(option)"
    >
      {{ option.title }}
    </button>
  </div>
</template>
