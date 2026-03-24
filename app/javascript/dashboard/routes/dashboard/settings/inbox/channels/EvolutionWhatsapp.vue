<script setup>
import { ref, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { required, requiredIf } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { isPhoneE164 } from 'shared/helpers/Validators';

const route = useRoute();
const routerInstance = useRouter();
const store = useStore();
const { t } = useI18n();

const inboxName = ref('');
const phoneNumber = ref('');
const evolutionInstance = ref('');
const apiKey = ref('');
const apiBaseUrl = ref('');
const useAutoProvision = ref(false);

function phoneFormat(value) {
  const v = value?.trim() ?? '';
  if (useAutoProvision.value && v === '') {
    return true;
  }
  return isPhoneE164(v);
}

const rules = computed(() => ({
  inboxName: { required },
  phoneNumber: {
    required: requiredIf(() => !useAutoProvision.value),
    phoneFormat,
  },
  evolutionInstance: {
    required: requiredIf(() => !useAutoProvision.value),
  },
  apiKey: {
    required: requiredIf(() => !useAutoProvision.value),
  },
}));

const v$ = useVuelidate(rules, {
  inboxName,
  phoneNumber,
  evolutionInstance,
  apiKey,
});

const uiFlags = useMapGetter('inboxes/getUIFlags');

const isCreating = computed(() => uiFlags.value?.isCreating);

const submitLabel = computed(() =>
  useAutoProvision.value
    ? t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.CONTINUE_TO_QR')
    : t('INBOX_MGMT.ADD.WHATSAPP.SUBMIT_BUTTON')
);

const webhookUrl = computed(() =>
  typeof window !== 'undefined' ? `${window.location.origin}/webhooks/evolution` : ''
);

async function createChannel() {
  v$.value.$touch();
  if (v$.value.$invalid) {
    return;
  }

  try {
    let whatsappChannel;
    if (useAutoProvision.value) {
      const channelPayload = {
        type: 'whatsapp',
        provider: 'evolution_api',
        provider_config: {
          auto_provision: true,
        },
      };
      const trimmedPhone = phoneNumber.value?.trim();
      if (trimmedPhone) {
        channelPayload.phone_number = trimmedPhone;
      }
      whatsappChannel = await store.dispatch('inboxes/createChannel', {
        name: inboxName.value?.trim(),
        channel: channelPayload,
      });
      routerInstance.replace({
        name: 'settings_inboxes_evolution_qr',
        params: {
          accountId: route.params.accountId,
          inbox_id: whatsappChannel.id,
        },
      });
    } else {
      const providerConfig = {
        evolution_instance: evolutionInstance.value?.trim(),
        api_key: apiKey.value,
      };
      if (apiBaseUrl.value?.trim()) {
        providerConfig.api_base_url = apiBaseUrl.value.trim();
      }
      whatsappChannel = await store.dispatch('inboxes/createChannel', {
        name: inboxName.value?.trim(),
        channel: {
          type: 'whatsapp',
          phone_number: phoneNumber.value?.trim(),
          provider: 'evolution_api',
          provider_config: providerConfig,
        },
      });
      routerInstance.replace({
        name: 'settings_inboxes_add_agents',
        params: {
          accountId: route.params.accountId,
          inbox_id: whatsappChannel.id,
        },
      });
    }
  } catch (error) {
    useAlert(
      error.message || t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE')
    );
  }
}
</script>

<template>
  <form class="flex flex-wrap flex-col mx-0" @submit.prevent="createChannel()">
    <div class="flex-shrink-0 flex-grow-0 mb-4">
      <label class="flex items-start gap-2 cursor-pointer text-sm text-n-slate-11">
        <input v-model="useAutoProvision" type="checkbox" class="mt-1" />
        <span>{{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.AUTO_CONNECT_TOGGLE') }}</span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.inboxName.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
        <input
          v-model="inboxName"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER')"
          @blur="v$.inboxName.$touch"
        />
        <span v-if="v$.inboxName.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.ERROR') }}
        </span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.phoneNumber.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.LABEL') }}
        <input
          v-model="phoneNumber"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.PLACEHOLDER')"
          @blur="v$.phoneNumber.$touch"
        />
        <span v-if="v$.phoneNumber.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.ERROR') }}
        </span>
      </label>
      <p
        v-if="useAutoProvision"
        class="mt-1 text-xs text-n-slate-10"
      >
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.PHONE_OPTIONAL_AUTO') }}
      </p>
    </div>

    <template v-if="!useAutoProvision">
      <div class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.evolutionInstance.$error }">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.INSTANCE_NAME_LABEL') }}
          <input
            v-model="evolutionInstance"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.INSTANCE_NAME_PLACEHOLDER')
            "
            @blur="v$.evolutionInstance.$touch"
          />
          <span v-if="v$.evolutionInstance.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.INSTANCE_NAME_ERROR') }}
          </span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.apiKey.$error }">
          <span>{{ $t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.LABEL') }}</span>
          <input
            v-model="apiKey"
            type="text"
            :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.PLACEHOLDER')"
            @blur="v$.apiKey.$touch"
          />
          <span v-if="v$.apiKey.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.ERROR') }}
          </span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0">
        <label>
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.API_BASE_URL_LABEL') }}
          <input
            v-model="apiBaseUrl"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.API_BASE_URL_PLACEHOLDER')
            "
          />
        </label>
      </div>

      <div
        v-if="webhookUrl"
        class="flex-shrink-0 flex-grow-0 rounded-lg border border-n-weak bg-n-slate-2 p-4"
      >
        <p class="mb-1 text-sm font-medium text-n-slate-12">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.WEBHOOK_TITLE') }}
        </p>
        <p class="mb-2 text-sm text-n-slate-11">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.WEBHOOK_DESCRIPTION') }}
        </p>
        <woot-code :script="webhookUrl" lang="plaintext" />
      </div>
    </template>

    <div class="w-full">
      <NextButton
        type="submit"
        :label="submitLabel"
        :is-loading="isCreating"
      />
    </div>
  </form>
</template>
