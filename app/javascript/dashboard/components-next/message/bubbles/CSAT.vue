<script setup>
import BaseBubble from './Base.vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../provider.js';

const { content } = useMessageContext();
const { t } = useI18n();
</script>

<template>
  <BaseBubble class="px-4 py-3" data-bubble-name="csat">
    <h4>{{ content || t('CONVERSATION.CSAT_REPLY_MESSAGE') }}</h4>
    <!-- CSAT responses (rating/feedback) should not be visible to agents in the conversation timeline -->
  </BaseBubble>
</template>
