<script setup>
import { onMounted, ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AccountAPI from 'dashboard/api/account';

import BillingMeter from '../billing/components/BillingMeter.vue';
import BillingCard from '../billing/components/BillingCard.vue';
import DetailItem from '../billing/components/DetailItem.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';

const { t } = useI18n();

const isLoading = ref(true);
const hasError = ref(false);
const usage = ref({});

const formatBytes = bytes => {
  if (!bytes || bytes === 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${(bytes / Math.pow(1024, i)).toFixed(2)} ${units[i]}`;
};

const storageFormatted = computed(() => {
  return formatBytes(usage.value.storage_bytes?.current || 0);
});

const fetchUsage = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await AccountAPI.getUsage();
    usage.value = data.usage;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

onMounted(fetchUsage);
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="$t('USAGE_SETTINGS.LOADING')"
    :no-records-found="hasError"
    :no-records-message="$t('USAGE_SETTINGS.ERROR')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="$t('USAGE_SETTINGS.TITLE')"
        :description="$t('USAGE_SETTINGS.DESCRIPTION')"
        feature-name="usage"
      />
    </template>
    <template #body>
      <section class="grid gap-4">
        <BillingCard
          :title="$t('USAGE_SETTINGS.RESOURCE_LIMITS')"
          :description="$t('USAGE_SETTINGS.RESOURCE_LIMITS_DESC')"
        >
          <div class="px-5 space-y-4">
            <BillingMeter
              v-if="usage.agents"
              :title="$t('USAGE_SETTINGS.AGENTS')"
              :consumed="usage.agents.current"
              :total-count="usage.agents.limit"
            />
            <BillingMeter
              v-if="usage.inboxes"
              :title="$t('USAGE_SETTINGS.INBOXES')"
              :consumed="usage.inboxes.current"
              :total-count="usage.inboxes.limit"
            />
          </div>
        </BillingCard>

        <BillingCard
          :title="$t('USAGE_SETTINGS.RESOURCE_COUNTS')"
          :description="$t('USAGE_SETTINGS.RESOURCE_COUNTS_DESC')"
        >
          <div
            class="grid grid-cols-2 lg:grid-cols-4 gap-2 divide-x divide-n-weak px-1"
          >
            <DetailItem
              v-if="usage.contacts"
              :label="$t('USAGE_SETTINGS.CONTACTS')"
              :value="String(usage.contacts.current)"
            />
            <DetailItem
              v-if="usage.conversations"
              :label="$t('USAGE_SETTINGS.CONVERSATIONS')"
              :value="String(usage.conversations.current)"
            />
            <DetailItem
              v-if="usage.messages"
              :label="$t('USAGE_SETTINGS.MESSAGES')"
              :value="String(usage.messages.current)"
            />
            <DetailItem
              v-if="usage.teams"
              :label="$t('USAGE_SETTINGS.TEAMS')"
              :value="String(usage.teams.current)"
            />
          </div>
          <div
            class="grid grid-cols-2 lg:grid-cols-4 gap-2 divide-x divide-n-weak px-1 mt-2"
          >
            <DetailItem
              v-if="usage.labels"
              :label="$t('USAGE_SETTINGS.LABELS')"
              :value="String(usage.labels.current)"
            />
            <DetailItem
              v-if="usage.campaigns"
              :label="$t('USAGE_SETTINGS.CAMPAIGNS')"
              :value="String(usage.campaigns.current)"
            />
            <DetailItem
              v-if="usage.automation_rules"
              :label="$t('USAGE_SETTINGS.AUTOMATION_RULES')"
              :value="String(usage.automation_rules.current)"
            />
            <DetailItem
              v-if="usage.canned_responses"
              :label="$t('USAGE_SETTINGS.CANNED_RESPONSES')"
              :value="String(usage.canned_responses.current)"
            />
          </div>
          <div
            class="grid grid-cols-2 lg:grid-cols-4 gap-2 divide-x divide-n-weak px-1 mt-2"
          >
            <DetailItem
              v-if="usage.webhooks"
              :label="$t('USAGE_SETTINGS.WEBHOOKS')"
              :value="String(usage.webhooks.current)"
            />
          </div>
        </BillingCard>

        <BillingCard
          :title="$t('USAGE_SETTINGS.STORAGE')"
          :description="$t('USAGE_SETTINGS.STORAGE_DESC')"
        >
          <div class="px-5">
            <DetailItem
              :label="$t('USAGE_SETTINGS.STORAGE_USED')"
              :value="storageFormatted"
            />
          </div>
        </BillingCard>
      </section>
    </template>
  </SettingsLayout>
</template>
