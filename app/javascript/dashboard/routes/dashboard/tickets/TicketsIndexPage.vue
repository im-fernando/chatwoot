<script setup>
import { ref, onMounted, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import TicketsAPI from 'dashboard/api/tickets';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();

const tickets = ref([]);
const meta = ref({ count: 0, current_page: 1 });
const statusFilter = ref('');
const isLoading = ref(true);

const load = async () => {
  isLoading.value = true;
  try {
    const params = { page: 1 };
    if (statusFilter.value) params.status = statusFilter.value;
    const { data } = await TicketsAPI.get(params);
    tickets.value = data.payload || [];
    meta.value = data.meta || { count: 0, current_page: 1 };
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);
watch(statusFilter, load);

const goNew = () => {
  router.push({
    name: 'tickets_dashboard_new',
    params: { accountId: accountId.value },
  });
};

const goShow = id => {
  router.push({
    name: 'tickets_dashboard_show',
    params: { accountId: accountId.value, displayId: String(id) },
  });
};

const statusLabel = s =>
  ({
    open: t('TICKETS.STATUS_OPEN'),
    pending: t('TICKETS.STATUS_PENDING'),
    resolved: t('TICKETS.STATUS_RESOLVED'),
  }[s] || s);
</script>

<template>
  <div class="flex flex-col w-full max-w-5xl mx-auto p-4 gap-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h1 class="m-0 text-xl font-semibold text-n-slate-12">
        {{ t('TICKETS.PAGE_TITLE') }}
      </h1>
      <Button
        :label="t('TICKETS.NEW')"
        icon="i-lucide-plus"
        sm
        @click="goNew"
      />
    </div>
    <div class="flex items-center gap-2">
      <label class="text-sm text-n-slate-11">{{ t('TICKETS.FILTER_STATUS') }}</label>
      <select
        v-model="statusFilter"
        class="text-sm rounded-lg border border-n-strong bg-n-solid-1 text-n-slate-12 px-3 py-2 outline-none focus:border-n-brand"
      >
        <option value="">{{ t('TICKETS.ALL') }}</option>
        <option value="open">{{ t('TICKETS.STATUS_OPEN') }}</option>
        <option value="pending">{{ t('TICKETS.STATUS_PENDING') }}</option>
        <option value="resolved">{{ t('TICKETS.STATUS_RESOLVED') }}</option>
      </select>
    </div>
    <div
      v-if="isLoading"
      class="py-12 text-center text-n-slate-11"
    >
      …
    </div>
    <div
      v-else-if="!tickets.length"
      class="flex flex-col items-center justify-center py-16 gap-2 text-center"
    >
      <p class="m-0 text-n-slate-11">{{ t('TICKETS.EMPTY') }}</p>
      <p class="m-0 text-sm text-n-slate-10">{{ t('TICKETS.EMPTY_HINT') }}</p>
      <Button
        :label="t('TICKETS.CREATE')"
        sm
        class="mt-2"
        @click="goNew"
      />
    </div>
    <ul
      v-else
      class="flex flex-col gap-2 p-0 m-0 list-none"
    >
      <li
        v-for="tk in tickets"
        :key="tk.internal_id"
      >
        <button
          type="button"
          class="flex flex-col w-full gap-1 p-4 text-left rounded-xl border border-n-weak bg-n-solid-1 hover:bg-n-alpha-2 transition-colors"
          @click="goShow(tk.id)"
        >
          <div class="flex items-center justify-between gap-2">
            <span class="text-sm font-semibold text-n-brand">#{{ tk.id }}</span>
            <span
              class="text-xs px-2 py-0.5 rounded-md bg-n-alpha-2 text-n-slate-11"
            >{{ statusLabel(tk.status) }}</span>
          </div>
          <span class="text-base font-medium text-n-slate-12">{{ tk.title }}</span>
          <span
            v-if="tk.description"
            class="text-sm text-n-slate-10 line-clamp-2"
          >{{ tk.description }}</span>
        </button>
      </li>
    </ul>
    <p
      v-if="!isLoading && tickets.length"
      class="text-sm text-n-slate-10"
    >
      {{ meta.count }} total
    </p>
  </div>
</template>
