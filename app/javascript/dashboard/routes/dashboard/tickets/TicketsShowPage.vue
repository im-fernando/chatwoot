<script setup>
import { ref, onMounted, watch } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper.js';
import TicketsAPI from 'dashboard/api/tickets';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const { accountId } = useAccount();

const ticket = ref(null);
const isLoading = ref(true);
const newComment = ref('');
const postingComment = ref(false);
const linkConvId = ref('');
const linking = ref(false);

const displayId = () => route.params.displayId;

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await TicketsAPI.show(displayId());
    ticket.value = data.payload;
  } catch {
    ticket.value = null;
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);
watch(
  () => route.params.displayId,
  () => load()
);

const convUrl = displayIdConv =>
  frontendURL(
    `accounts/${accountId.value}/conversations/${displayIdConv}`
  );

const saveStatus = async () => {
  if (!ticket.value) return;
  try {
    await TicketsAPI.update(displayId(), {
      ticket: { status: ticket.value.status },
    });
    useAlert(t('TICKETS.SAVED'));
    await load();
  } catch {
    useAlert(t('TICKETS.ERROR_GENERIC'));
  }
};

const postComment = async () => {
  if (!newComment.value.trim()) return;
  postingComment.value = true;
  try {
    const { data } = await TicketsAPI.addComment(
      displayId(),
      newComment.value.trim()
    );
    ticket.value.comments = [...(ticket.value.comments || []), data.payload];
    newComment.value = '';
    useAlert(t('TICKETS.UPDATE_POSTED'));
  } catch {
    useAlert(t('TICKETS.ERROR_GENERIC'));
  } finally {
    postingComment.value = false;
  }
};

const linkConversation = async () => {
  const id = parseInt(String(linkConvId.value).replace(/^#/, ''), 10);
  if (!id) return;
  linking.value = true;
  try {
    await TicketsAPI.linkConversation(displayId(), id);
    useAlert(t('TICKETS.LINKED'));
    linkConvId.value = '';
    await load();
  } catch (e) {
    useAlert(e.response?.data?.error || t('TICKETS.ERROR_GENERIC'));
  } finally {
    linking.value = false;
  }
};

const unlinkConversation = async convDisplayId => {
  try {
    await TicketsAPI.unlinkConversation(displayId(), convDisplayId);
    useAlert(t('TICKETS.UNLINKED'));
    await load();
  } catch {
    useAlert(t('TICKETS.ERROR_GENERIC'));
  }
};

const back = () => {
  router.push({
    name: 'tickets_dashboard_index',
    params: { accountId: accountId.value },
  });
};
</script>

<template>
  <div
    v-if="isLoading"
    class="p-8 text-center text-n-slate-11"
  >
    …
  </div>
  <div
    v-else-if="!ticket"
    class="p-8 text-center text-n-slate-11"
  >
    {{ t('TICKETS.ERROR_GENERIC') }}
    <Button
      class="mt-4"
      :label="t('TICKETS.BACK_TO_LIST')"
      sm
      @click="back"
    />
  </div>
  <div
    v-else
    class="flex flex-col w-full max-w-3xl mx-auto p-4 gap-6"
  >
    <Button
      :label="t('TICKETS.BACK_TO_LIST')"
      icon="i-lucide-arrow-left"
      sm
      faded
      slate
      @click="back"
    />
    <div class="flex flex-wrap items-start justify-between gap-4">
      <div class="min-w-0 flex-1">
        <p class="m-0 text-sm font-semibold text-n-brand">
          #{{ ticket.id }}
        </p>
        <h1 class="mt-1 mb-0 text-xl font-semibold text-n-slate-12">
          {{ ticket.title }}
        </h1>
        <p
          v-if="ticket.description"
          class="mt-2 mb-0 text-n-slate-11 whitespace-pre-wrap"
        >
          {{ ticket.description }}
        </p>
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-10">{{ t('TICKETS.STATUS') }}</label>
        <select
          v-model="ticket.status"
          class="text-sm rounded-lg border border-n-strong bg-n-solid-1 text-n-slate-12 px-3 py-2 outline-none focus:border-n-brand"
          @change="saveStatus"
        >
          <option value="open">
            {{ t('TICKETS.STATUS_OPEN') }}
          </option>
          <option value="pending">
            {{ t('TICKETS.STATUS_PENDING') }}
          </option>
          <option value="resolved">
            {{ t('TICKETS.STATUS_RESOLVED') }}
          </option>
        </select>
      </div>
    </div>

    <section>
      <h2 class="mt-0 mb-3 text-base font-semibold text-n-slate-12">
        {{ t('TICKETS.LINKED_CONVERSATIONS') }}
      </h2>
      <div class="flex flex-wrap gap-2 mb-3">
        <input
          v-model="linkConvId"
          type="text"
          :placeholder="t('TICKETS.CONVERSATION_DISPLAY_ID')"
          class="flex-1 min-w-[8rem] px-3 py-2 rounded-lg border border-n-strong bg-n-solid-1 text-n-slate-12 outline-none focus:border-n-brand"
        >
        <Button
          :label="t('TICKETS.ADD_CONVERSATION')"
          sm
          :is-loading="linking"
          @click="linkConversation"
        />
      </div>
      <ul
        v-if="ticket.conversations?.length"
        class="flex flex-col gap-2 p-0 m-0 list-none"
      >
        <li
          v-for="c in ticket.conversations"
          :key="c.display_id"
          class="flex items-center justify-between gap-2 p-3 rounded-lg border border-n-weak bg-n-solid-2"
        >
          <div class="min-w-0">
            <span class="text-sm font-medium text-n-slate-12">#{{ c.display_id }}</span>
            <span class="text-sm text-n-slate-10 mx-2">{{ c.contact_name }}</span>
            <span class="text-xs text-n-slate-10">{{ c.inbox_name }}</span>
          </div>
          <div class="flex items-center gap-2 flex-shrink-0">
            <router-link
              :to="convUrl(c.display_id)"
              class="text-sm text-n-brand hover:underline"
            >
              {{ t('TICKETS.OPEN_CONVERSATION') }}
            </router-link>
            <Button
              :label="t('TICKETS.UNLINK')"
              sm
              slate
              faded
              @click="unlinkConversation(c.display_id)"
            />
          </div>
        </li>
      </ul>
      <p
        v-else
        class="text-sm text-n-slate-10 m-0"
      >
        —
      </p>
    </section>

    <section>
      <h2 class="mt-0 mb-3 text-base font-semibold text-n-slate-12">
        {{ t('TICKETS.UPDATES') }}
      </h2>
      <div class="flex flex-col gap-2 mb-4">
        <textarea
          v-model="newComment"
          rows="3"
          :placeholder="t('TICKETS.NEW_UPDATE')"
          class="w-full px-3 py-2 rounded-lg border border-n-strong bg-n-solid-1 text-n-slate-12 outline-none focus:border-n-brand resize-y"
        />
        <Button
          :label="t('TICKETS.POST_UPDATE')"
          sm
          :is-loading="postingComment"
          @click="postComment"
        />
      </div>
      <ul
        class="flex flex-col gap-3 p-0 m-0 list-none"
      >
        <li
          v-for="cm in ticket.comments"
          :key="cm.id"
          class="p-3 rounded-lg border border-n-weak bg-n-solid-1"
        >
          <div class="flex items-center justify-between gap-2 mb-1">
            <span class="text-sm font-medium text-n-slate-12">{{ cm.user?.name }}</span>
            <span class="text-xs text-n-slate-10">{{ new Date(cm.created_at * 1000).toLocaleString() }}</span>
          </div>
          <p class="m-0 text-sm text-n-slate-11 whitespace-pre-wrap">
            {{ cm.content }}
          </p>
        </li>
      </ul>
    </section>
  </div>
</template>
