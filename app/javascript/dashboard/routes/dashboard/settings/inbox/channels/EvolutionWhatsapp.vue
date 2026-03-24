<script setup>
import { ref, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
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

function phoneFormat(value) {
  const v = value?.trim() ?? '';
  if (v === '') {
    return true;
  }
  return isPhoneE164(v);
}

const rules = computed(() => ({
  inboxName: { required },
  phoneNumber: { phoneFormat },
}));

const v$ = useVuelidate(rules, {
  inboxName,
  phoneNumber,
});

const uiFlags = useMapGetter('inboxes/getUIFlags');

const isCreating = computed(() => uiFlags.value?.isCreating);

async function createChannel() {
  v$.value.$touch();
  if (v$.value.$invalid) {
    return;
  }

  try {
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
    const whatsappChannel = await store.dispatch('inboxes/createChannel', {
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
  } catch (error) {
    useAlert(error.message || t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE'));
  }
}
</script>

<template>
  <form class="flex flex-wrap flex-col mx-0" @submit.prevent="createChannel()">
    <p class="mb-4 text-sm text-n-slate-11">
      {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.AUTO_CONNECT_TOGGLE') }}
    </p>

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
      <p class="mt-1 text-xs text-n-slate-10">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.PHONE_OPTIONAL_AUTO') }}
      </p>
    </div>

    <div class="w-full">
      <NextButton
        type="submit"
        :label="$t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.CONTINUE_TO_QR')"
        :is-loading="isCreating"
      />
    </div>
  </form>
</template>
