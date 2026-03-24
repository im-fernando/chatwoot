<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import QRCode from 'qrcode';
import InboxesAPI from 'dashboard/api/inboxes';
import NextButton from 'dashboard/components-next/button/Button.vue';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();

const inboxId = computed(
  () => route.params.inbox_id ?? route.params.inboxId
);

const continueAfterConnectLabel = computed(() => {
  if (route.name === 'settings_inbox_evolution_qr') {
    return t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.BACK_TO_INBOX_SETTINGS');
  }
  return t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.CONTINUE_TO_AGENTS');
});
const qrDataUrl = ref('');
const pairingCode = ref('');
const loadError = ref('');
const isLoading = ref(true);
const isConnected = ref(false);
let pollTimer = null;

function normalizeDataUrl(b64) {
  const s = String(b64);
  if (s.startsWith('data:')) return s;
  return `data:image/png;base64,${s}`;
}

async function buildQrFromPayload(payload) {
  if (!payload || typeof payload !== 'object') {
    return;
  }

  const b64 = payload.base64 || payload.qrcode?.base64;
  if (b64) {
    qrDataUrl.value = normalizeDataUrl(b64);
    return;
  }

  const textForQr = payload.code || payload.qrcode?.code;
  if (textForQr && typeof textForQr === 'string') {
    try {
      qrDataUrl.value = await QRCode.toDataURL(textForQr, {
        width: 280,
        margin: 2,
      });
    } catch {
      loadError.value = t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.QR_GENERATION_ERROR');
    }
  }

  const pc = payload.pairingCode || payload.qrcode?.pairingCode;
  if (pc) {
    pairingCode.value = String(pc);
  }
}

async function fetchConnect() {
  isLoading.value = true;
  loadError.value = '';
  qrDataUrl.value = '';
  pairingCode.value = '';

  try {
    const { data } = await InboxesAPI.getEvolutionConnect(inboxId.value);
    if (data.status && Number(data.status) >= 400) {
      loadError.value =
        data.data?.message?.join?.(', ') ||
        data.data?.error ||
        t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.QR_FETCH_ERROR');
      return;
    }
    await buildQrFromPayload(data.data);
    if (!qrDataUrl.value && !pairingCode.value) {
      loadError.value = t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.QR_EMPTY');
    }
  } catch (e) {
    loadError.value =
      e?.response?.data?.message ||
      t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.QR_FETCH_ERROR');
  } finally {
    isLoading.value = false;
  }
}

async function pollConnection() {
  try {
    const { data } = await InboxesAPI.getEvolutionConnectionStatus(inboxId.value);
    const state = data.connection_state?.toString()?.toLowerCase();
    if (state === 'open') {
      isConnected.value = true;
      stopPolling();
    }
  } catch {
    // ignore transient errors while polling
  }
}

function startPolling() {
  stopPolling();
  pollTimer = setInterval(pollConnection, 3000);
}

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

async function goToNextAfterConnected() {
  await store.dispatch('inboxes/get');
  const accountId = route.params.accountId;
  if (route.name === 'settings_inboxes_evolution_qr') {
    router.replace({
      name: 'settings_inboxes_add_agents',
      params: {
        accountId,
        inbox_id: inboxId.value,
      },
    });
  } else {
    router.replace({
      name: 'settings_inbox_show',
      params: {
        accountId,
        inboxId: inboxId.value,
      },
    });
  }
}

onMounted(async () => {
  await pollConnection();
  if (isConnected.value) {
    isLoading.value = false;
    return;
  }
  await fetchConnect();
  startPolling();
});

onBeforeUnmount(() => {
  stopPolling();
});
</script>

<template>
  <div
    class="flex w-full flex-col items-center gap-6 py-6 mx-auto max-w-xl px-6"
  >
    <div class="w-full text-center">
      <h2 class="mb-2 text-base font-medium text-n-slate-12">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.QR_TITLE') }}
      </h2>
      <p class="text-sm leading-relaxed text-n-slate-11">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.QR_INSTRUCTION') }}
      </p>
    </div>

    <div
      v-if="isLoading"
      class="py-8 text-sm text-center text-n-slate-11"
    >
      {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.QR_LOADING') }}
    </div>

    <div
      v-else-if="loadError"
      class="w-full rounded-lg border border-n-weak bg-n-slate-2 p-4 text-sm text-center text-n-ruby-11"
    >
      {{ loadError }}
      <div class="mt-3 flex justify-center">
        <button
          type="button"
          class="text-sm font-medium text-n-brand underline"
          @click="fetchConnect"
        >
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.QR_REFRESH') }}
        </button>
      </div>
    </div>

    <div
      v-else-if="isConnected"
      class="w-full rounded-lg border border-n-weak bg-n-slate-2 p-4 text-sm text-center text-n-slate-12"
    >
      {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.QR_CONNECTED') }}
      <div class="mt-4 flex justify-center">
        <NextButton
          type="button"
          :label="continueAfterConnectLabel"
          @click="goToNextAfterConnected"
        />
      </div>
    </div>

    <div v-else class="flex w-full flex-col items-center gap-4 text-center">
      <div
        v-if="qrDataUrl"
        class="rounded-xl border border-n-weak bg-white p-4 mx-auto"
      >
        <img
          :src="qrDataUrl"
          alt=""
          class="block w-[280px] h-[280px] mx-auto"
        />
      </div>
      <div
        v-if="pairingCode"
        class="w-full text-sm text-n-slate-11 break-words"
      >
        <span class="font-medium text-n-slate-12">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.PAIRING_CODE') }}
        </span>
        {{ pairingCode }}
      </div>

      <button
        type="button"
        class="text-sm font-medium text-n-brand underline"
        @click="fetchConnect"
      >
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.QR_REFRESH') }}
      </button>

      <p class="text-xs text-n-slate-10 max-w-md">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.QR_POLL_HINT') }}
      </p>
    </div>
  </div>
</template>
