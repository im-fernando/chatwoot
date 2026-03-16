<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { required } from '@vuelidate/validators';
import router from '../../../../index';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { isPhoneE164OrEmpty } from 'shared/helpers/Validators';

export default {
  components: {
    NextButton,
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      inboxName: '',
      phoneNumber: '',
      evolutionInstance: '',
      apiKey: '',
      apiBaseUrl: '',
    };
  },
  computed: {
    ...mapGetters({ uiFlags: 'inboxes/getUIFlags' }),
    webhookUrl() {
      const base =
        typeof window !== 'undefined' ? window.location.origin : '';
      return base ? `${base}/webhooks/evolution` : '';
    },
  },
  validations: {
    inboxName: { required },
    phoneNumber: { required, isPhoneE164OrEmpty },
    evolutionInstance: { required },
    apiKey: { required },
  },
  methods: {
    async createChannel() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        return;
      }

      try {
        const providerConfig = {
          evolution_instance: this.evolutionInstance?.trim(),
          api_key: this.apiKey,
        };
        if (this.apiBaseUrl?.trim()) {
          providerConfig.api_base_url = this.apiBaseUrl.trim();
        }

        const whatsappChannel = await this.$store.dispatch(
          'inboxes/createChannel',
          {
            name: this.inboxName?.trim(),
            channel: {
              type: 'whatsapp',
              phone_number: this.phoneNumber,
              provider: 'evolution_api',
              provider_config: providerConfig,
            },
          }
        );

        router.replace({
          name: 'settings_inboxes_add_agents',
          params: {
            page: 'new',
            inbox_id: whatsappChannel.id,
          },
        });
      } catch (error) {
        useAlert(
          error.message || this.$t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE')
        );
      }
    },
  },
};
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
    </div>

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

    <div class="w-full">
      <NextButton
        type="submit"
        :label="$t('INBOX_MGMT.ADD.WHATSAPP.SUBMIT_BUTTON')"
        :is-loading="uiFlags.isCreating"
      />
    </div>
  </form>
</template>
