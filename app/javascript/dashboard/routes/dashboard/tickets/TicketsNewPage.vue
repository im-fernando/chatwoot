<script setup>
import { ref, onMounted } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import TicketsAPI from 'dashboard/api/tickets';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const { accountId } = useAccount();

const title = ref('');
const description = ref('');
const isSubmitting = ref(false);

onMounted(() => {
  const q = route.query.conversation_id;
  if (q) {
    description.value = '';
  }
});

const submit = async () => {
  if (!title.value.trim()) return;
  isSubmitting.value = true;
  try {
    const ticket = {
      title: title.value.trim(),
      description: description.value.trim() || undefined,
      status: 'open',
    };
    const cid = route.query.conversation_id;
    if (cid) {
      ticket.conversation_display_id = parseInt(String(cid), 10);
    }
    const { data } = await TicketsAPI.create({ ticket });
    useAlert(t('TICKETS.SAVED'));
    router.replace({
      name: 'tickets_dashboard_show',
      params: {
        accountId: accountId.value,
        displayId: String(data.payload.id),
      },
    });
  } catch (e) {
    const msg = e.response?.data?.error;
    useAlert(msg || t('TICKETS.ERROR_GENERIC'));
  } finally {
    isSubmitting.value = false;
  }
};

const back = () => {
  router.push({
    name: 'tickets_dashboard_index',
    params: { accountId: accountId.value },
  });
};
</script>

<template>
  <div class="flex flex-col w-full max-w-xl mx-auto p-4 gap-4">
    <Button
      :label="t('TICKETS.BACK_TO_LIST')"
      icon="i-lucide-arrow-left"
      sm
      faded
      slate
      @click="back"
    />
    <h1 class="m-0 text-xl font-semibold text-n-slate-12">
      {{ t('TICKETS.CREATE') }}
    </h1>
    <div class="flex flex-col gap-2">
      <label class="text-sm font-medium text-n-slate-11">{{ t('TICKETS.TITLE') }}</label>
      <input
        v-model="title"
        type="text"
        class="w-full px-3 py-2 rounded-lg border border-n-strong bg-n-solid-1 text-n-slate-12 outline-none focus:border-n-brand"
      >
    </div>
    <div class="flex flex-col gap-2">
      <label class="text-sm font-medium text-n-slate-11">{{ t('TICKETS.DESCRIPTION') }}</label>
      <textarea
        v-model="description"
        rows="5"
        class="w-full px-3 py-2 rounded-lg border border-n-strong bg-n-solid-1 text-n-slate-12 outline-none focus:border-n-brand resize-y min-h-[120px]"
      />
    </div>
    <div class="flex gap-2">
      <Button
        :label="t('TICKETS.CREATE')"
        :is-loading="isSubmitting"
        @click="submit"
      />
      <Button
        :label="t('GENERAL_SETTINGS.BACK')"
        slate
        faded
        @click="back"
      />
    </div>
  </div>
</template>
