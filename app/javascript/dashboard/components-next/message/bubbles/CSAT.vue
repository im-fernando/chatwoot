<script setup>
import { computed } from 'vue';
import BaseBubble from './Base.vue';
import { useI18n } from 'vue-i18n';
import { CSAT_RATINGS, CSAT_DISPLAY_TYPES } from 'shared/constants/messages';
import { useMessageContext } from '../provider.js';

const { contentAttributes, content } = useMessageContext();
const { t } = useI18n();

const response = computed(() => {
  return contentAttributes.value?.submittedValues?.csatSurveyResponse ?? {};
});

const isRatingSubmitted = computed(() => {
  return !!response.value.rating;
});

const displayType = computed(() => {
  return contentAttributes.value?.displayType || CSAT_DISPLAY_TYPES.EMOJI;
});

const isStarRating = computed(() => {
  return displayType.value === CSAT_DISPLAY_TYPES.STAR;
});

const rating = computed(() => {
  if (isRatingSubmitted.value) {
    return CSAT_RATINGS.find(
      csatOption => csatOption.value === response.value.rating
    );
  }

  return null;
});

const starRatingValue = computed(() => {
  return response.value.rating || 0;
});
</script>

<template>
  <BaseBubble class="px-4 py-3" data-bubble-name="csat">
    <h4>{{ content || t('CONVERSATION.CSAT_REPLY_MESSAGE') }}</h4>
    <!-- CSAT responses (rating/feedback) should not be visible to agents in the conversation timeline -->
  </BaseBubble>
</template>
