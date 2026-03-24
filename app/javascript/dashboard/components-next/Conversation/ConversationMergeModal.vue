<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import types from 'dashboard/store/mutation-types';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationApi from 'dashboard/api/inbox/conversation';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const dialogRef = ref(null);
const selectedSourceId = ref(null);
const retainOpenConversation = ref(true);
const isMerging = ref(false);

const getContactConversations = useMapGetter(
  'contactConversations/getAllConversationsByContactId'
);
const uiFlags = useMapGetter('contactConversations/getUIFlags');

const contactId = computed(() => props.conversation.meta?.sender?.id);

const isFetching = computed(() => uiFlags.value.isFetching);

const inboxIdOf = conv => conv?.inboxId ?? conv?.inbox_id;

const mergeCandidates = computed(() => {
  if (!contactId.value) return [];
  const targetInbox = inboxIdOf(props.conversation);
  if (targetInbox === undefined || targetInbox === null) return [];

  const list = getContactConversations.value(contactId.value) || [];
  const currentId = Number(props.conversation.id);

  return list.filter(c => {
    if (Number(c.id) === currentId) return false;
    return Number(inboxIdOf(c)) === Number(targetInbox);
  });
});

const statusLabel = status => {
  const key = `CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.${status}.TEXT`;
  const translated = t(key);
  return translated !== key ? translated : status;
};

const formatTime = conversation => {
  const ts = conversation?.timestamp;
  return ts ? shortTimestamp(dynamicTime(ts)) : '';
};

const selectConversation = id => {
  selectedSourceId.value = id;
};

const conversationPathForId = displayId => {
  const accountId = route.params.accountId;
  const { name, params } = route;

  if (name === 'conversation_through_inbox') {
    return frontendURL(
      conversationUrl({
        accountId,
        activeInbox: params.inbox_id,
        id: displayId,
      })
    );
  }
  if (name === 'conversations_through_label') {
    return frontendURL(
      conversationUrl({
        accountId,
        label: params.label,
        id: displayId,
      })
    );
  }
  if (name === 'conversations_through_team') {
    return frontendURL(
      conversationUrl({
        accountId,
        teamId: params.teamId,
        id: displayId,
      })
    );
  }
  if (name === 'conversations_through_folders') {
    return frontendURL(
      conversationUrl({
        accountId,
        foldersId: params.id,
        id: displayId,
      })
    );
  }
  if (name === 'conversation_through_mentions') {
    return frontendURL(
      conversationUrl({
        accountId,
        id: displayId,
        conversationType: 'mention',
      })
    );
  }
  if (name === 'conversation_through_unattended') {
    return frontendURL(
      conversationUrl({
        accountId,
        id: displayId,
        conversationType: 'unattended',
      })
    );
  }
  if (name === 'conversation_through_participating') {
    return frontendURL(
      conversationUrl({
        accountId,
        id: displayId,
        conversationType: 'participating',
      })
    );
  }
  return frontendURL(conversationUrl({ accountId, id: displayId }));
};

const open = async () => {
  selectedSourceId.value = null;
  retainOpenConversation.value = true;
  if (!contactId.value) return;
  await store.dispatch('contactConversations/get', contactId.value);
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
};

const handleMerge = async () => {
  if (!selectedSourceId.value || isMerging.value) return;

  const currentConvId = Number(props.conversation.id);
  const selectedId = Number(selectedSourceId.value);

  isMerging.value = true;
  try {
    const { data } = await ConversationApi.merge({
      conversationId: props.conversation.id,
      sourceConversationId: selectedSourceId.value,
      retainConversationId: retainOpenConversation.value
        ? undefined
        : selectedSourceId.value,
    });

    const keptId = Number(data.id);
    const removedId = retainOpenConversation.value ? selectedId : currentConvId;

    store.commit(types.DELETE_CONVERSATION, removedId);
    await store.dispatch('getConversation', keptId);
    await store.dispatch('reloadConversationAfterMerge', keptId);
    await store.dispatch('contactConversations/get', contactId.value);

    if (keptId !== currentConvId) {
      router.replace({ path: conversationPathForId(keptId) });
    }

    useAlert(t('CONVERSATION.MERGE.SUCCESS'));
    close();
  } catch (error) {
    const message =
      error.response?.data?.error || t('CONVERSATION.MERGE.ERROR');
    useAlert(message);
  } finally {
    isMerging.value = false;
  }
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="2xl"
    overflow-y-auto
    :title="t('CONVERSATION.MERGE.TITLE')"
    :description="t('CONVERSATION.MERGE.DESCRIPTION')"
    :confirm-button-label="t('CONVERSATION.MERGE.CONFIRM')"
    :cancel-button-label="t('DIALOG.BUTTONS.CANCEL')"
    :disable-confirm-button="!selectedSourceId"
    :is-loading="isMerging"
    @confirm="handleMerge"
  >
    <div class="flex flex-col gap-4 min-h-[8rem] max-h-[28rem]">
      <div
        v-if="isFetching"
        class="flex items-center justify-center py-10 text-n-slate-11"
      >
        <Spinner />
      </div>
      <p
        v-else-if="!mergeCandidates.length"
        class="py-6 text-sm leading-6 text-center text-n-slate-11"
      >
        {{ t('CONVERSATION.MERGE.EMPTY') }}
      </p>
      <template v-else>
        <ul class="flex flex-col gap-1 p-0 m-0 overflow-y-auto list-none">
          <li v-for="c in mergeCandidates" :key="c.id">
            <button
              type="button"
              class="flex flex-col w-full gap-1 px-3 py-3 text-left transition-colors rounded-lg border border-transparent"
              :class="
                selectedSourceId === c.id
                  ? 'bg-n-alpha-2 border-n-strong'
                  : 'hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3'
              "
              @click="selectConversation(c.id)"
            >
              <div class="flex items-center justify-between gap-2">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('CONVERSATION.MERGE.CONVERSATION_LABEL', { id: c.id }) }}
                </span>
                <span class="text-xs text-n-slate-10">
                  {{ formatTime(c) }}
                </span>
              </div>
              <span class="text-xs text-n-slate-11">
                {{ statusLabel(c.status) }}
              </span>
            </button>
          </li>
        </ul>

        <div v-if="selectedSourceId" class="flex flex-col gap-2">
          <p class="text-xs font-medium text-n-slate-11">
            {{ t('CONVERSATION.MERGE.KEEP_LABEL') }}
          </p>
          <div class="flex flex-col gap-1.5">
            <button
              type="button"
              class="px-3 py-2 text-sm text-left transition-colors rounded-lg border"
              :class="
                retainOpenConversation
                  ? 'border-n-strong bg-n-alpha-2 text-n-slate-12'
                  : 'border-transparent bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2 dark:bg-n-alpha-3'
              "
              @click="retainOpenConversation = true"
            >
              {{
                t('CONVERSATION.MERGE.KEEP_CURRENT', {
                  id: conversation.id,
                })
              }}
            </button>
            <button
              type="button"
              class="px-3 py-2 text-sm text-left transition-colors rounded-lg border"
              :class="
                !retainOpenConversation
                  ? 'border-n-strong bg-n-alpha-2 text-n-slate-12'
                  : 'border-transparent bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2 dark:bg-n-alpha-3'
              "
              @click="retainOpenConversation = false"
            >
              {{
                t('CONVERSATION.MERGE.KEEP_SELECTED', {
                  id: selectedSourceId,
                })
              }}
            </button>
          </div>
        </div>
      </template>
    </div>
  </Dialog>
</template>
