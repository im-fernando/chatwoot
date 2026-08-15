<script setup>
import { computed } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useMessageContext } from '../provider.js';

/**
 * Options offered by an incoming WhatsApp interactive message (buttons, list or template).
 * Picking one quotes the prompt and drops the option text into the reply box, so the agent
 * answers exactly like a customer tapping the button would.
 */
const { id, conversationId, contentAttributes } = useMessageContext();

const options = computed(
  () => contentAttributes.value?.interactiveOptions ?? []
);

const selectOption = option => {
  if (option.url) {
    window.open(option.url, '_blank', 'noopener');
    return;
  }

  LocalStorage.updateJsonStore(
    LOCAL_STORAGE_KEYS.MESSAGE_REPLY_TO,
    conversationId.value,
    id.value
  );
  emitter.emit(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE);
  emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, option.title);
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
