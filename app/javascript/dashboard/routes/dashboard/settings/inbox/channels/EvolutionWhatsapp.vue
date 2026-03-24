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

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();

const inboxName = ref('');

const rules = {
  inboxName: { required },
};

const v$ = useVuelidate(rules, { inboxName });

const uiFlags = useMapGetter('inboxes/getUIFlags');

const isCreating = computed(() => uiFlags.value?.isCreating);

async function createChannel() {
  v$.value.$touch();
  if (v$.value.$invalid) {
    return;
  }

  try {
    const whatsappChannel = await store.dispatch('inboxes/createChannel', {
      name: inboxName.value?.trim(),
      channel: {
        type: 'whatsapp',
        provider: 'evolution_api',
        provider_config: {
          auto_provision: true,
        },
      },
    });

    router.replace({
      name: 'settings_inboxes_evolution_qr',
      params: {
        accountId: route.params.accountId,
        inbox_id: whatsappChannel.id,
      },
    });
  } catch (error) {
    useAlert(
      error.message || t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE')
    );
  }
}
</script>

<template>
  <form class="flex flex-wrap flex-col mx-0" @submit.prevent="createChannel()">
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

    <div class="w-full">
      <NextButton
        type="submit"
        :label="$t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION_API.CONTINUE_TO_QR')"
        :is-loading="isCreating"
      />
    </div>
  </form>
</template>
