<script setup>
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import TicketsAPI from 'dashboard/api/tickets';
import Button from 'dashboard/components-next/button/Button.vue';
import Modal from 'dashboard/components/Modal.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  conversationDisplayId: { type: [Number, String], required: true },
});

const emit = defineEmits(['close', 'update:show']);

const { t } = useI18n();

const localShow = computed({
  get: () => props.show,
  set: v => {
    if (!v) emit('close');
    emit('update:show', v);
  },
});

const ticketDisplayId = ref('');
const loading = ref(false);

watch(
  () => props.show,
  v => {
    if (v) ticketDisplayId.value = '';
  }
);

const onModalClose = () => {
  emit('close');
  emit('update:show', false);
};

const submit = async () => {
  const tid = parseInt(String(ticketDisplayId.value).replace(/^#/, ''), 10);
  if (!tid) return;
  loading.value = true;
  try {
    await TicketsAPI.linkConversation(
      tid,
      parseInt(String(props.conversationDisplayId), 10)
    );
    useAlert(t('CONVERSATION.TICKETS.LINK_SUCCESS'));
    onModalClose();
  } catch (e) {
    useAlert(e.response?.data?.error || t('TICKETS.ERROR_GENERIC'));
  } finally {
    loading.value = false;
  }
};
</script>

<template>
  <Modal
    v-model:show="localShow"
    :on-close="onModalClose"
  >
    <div class="flex flex-col gap-4 p-6 max-w-md">
      <h3 class="m-0 text-lg font-semibold text-n-slate-12">
        {{ t('CONVERSATION.TICKETS.LINK_TITLE') }}
      </h3>
      <div class="flex flex-col gap-1">
        <label class="text-sm text-n-slate-11">{{ t('CONVERSATION.TICKETS.TICKET_NUMBER_PLACEHOLDER') }}</label>
        <input
          v-model="ticketDisplayId"
          type="text"
          :placeholder="t('CONVERSATION.TICKETS.TICKET_NUMBER_PLACEHOLDER')"
          class="w-full px-3 py-2 rounded-lg border border-n-strong bg-n-solid-1 text-n-slate-12 outline-none focus:border-n-brand"
        >
      </div>
      <div class="flex justify-end gap-2">
        <Button
          :label="t('DIALOG.BUTTONS.CANCEL')"
          slate
          faded
          sm
          @click="onModalClose"
        />
        <Button
          :label="t('CONVERSATION.TICKETS.SUBMIT_LINK')"
          sm
          :is-loading="loading"
          @click="submit"
        />
      </div>
    </div>
  </Modal>
</template>
