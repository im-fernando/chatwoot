<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { OnClickOutside } from '@vueuse/components';
import { createContactSearcher } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';

const MAX_CONTACTS = 5;

const props = defineProps({
  selectedContacts: {
    type: Array,
    default: () => [],
  },
  /** When true, only the toolbar button + dropdown (chips live in ShareEvolutionContactsChips). */
  toolbarOnly: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:selectedContacts']);

const { t } = useI18n();
const searchContacts = createContactSearcher();
const query = ref('');
const results = ref([]);
const isOpen = ref(false);
const isSearching = ref(false);

const selectedIds = computed(() => new Set(props.selectedContacts.map(c => c.id)));

const runSearch = async () => {
  const q = query.value.trim();
  if (q.length < 2) {
    results.value = [];
    return;
  }
  isSearching.value = true;
  try {
    const payload = await searchContacts(q);
    if (payload === null) return;
    results.value = (payload || []).filter(
      c => c.phoneNumber && !selectedIds.value.has(c.id)
    );
  } finally {
    isSearching.value = false;
  }
};

const debouncedSearch = debounce(runSearch, 400, false);

watch(query, () => {
  debouncedSearch();
});

function toggleOpen() {
  isOpen.value = !isOpen.value;
  if (isOpen.value) {
    query.value = '';
    results.value = [];
  }
}

function closeDropdown() {
  if (isOpen.value) {
    isOpen.value = false;
  }
}

function addContact(contact) {
  if (props.selectedContacts.length >= MAX_CONTACTS) {
    useAlert(
      t('CONVERSATION.REPLYBOX.SHARE_SAVED_CONTACTS_MAX', {
        count: MAX_CONTACTS,
      })
    );
    return;
  }
  if (!contact.phoneNumber) {
    useAlert(t('CONVERSATION.REPLYBOX.SHARE_SAVED_CONTACTS_NO_PHONE'));
    return;
  }
  emit('update:selectedContacts', [
    ...props.selectedContacts,
    {
      id: contact.id,
      name: contact.name,
      phoneNumber: contact.phoneNumber,
    },
  ]);
  query.value = '';
  results.value = [];
}

function removeContact(id) {
  emit(
    'update:selectedContacts',
    props.selectedContacts.filter(c => c.id !== id)
  );
}

function labelFor(contact) {
  const phone = contact.phoneNumber || '';
  return phone ? `${contact.name} (${phone})` : contact.name;
}
</script>

<template>
  <div
    :class="
      toolbarOnly
        ? 'inline-flex flex-shrink-0 items-center'
        : 'flex flex-col gap-2 w-full'
    "
  >
    <div
      v-if="!toolbarOnly && selectedContacts.length"
      class="flex flex-wrap gap-1.5"
    >
      <div
        v-for="c in selectedContacts"
        :key="c.id"
        class="inline-flex gap-1 items-center px-2 py-0.5 max-w-full text-xs rounded-md bg-n-alpha-2 text-n-slate-12"
      >
        <span class="truncate">{{ labelFor(c) }}</span>
        <button
          type="button"
          class="flex-shrink-0 text-n-slate-11 hover:text-n-slate-12"
          :aria-label="$t('CONVERSATION.REPLYBOX.SHARE_SAVED_CONTACTS_REMOVE')"
          @click="removeContact(c.id)"
        >
          <span class="i-lucide-x size-3.5" />
        </button>
      </div>
    </div>
    <OnClickOutside @trigger="closeDropdown">
      <div class="relative inline-flex">
        <NextButton
          v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.SHARE_SAVED_CONTACT_TOOLTIP')"
          icon="i-ph-user-plus"
          slate
          faded
          sm
          @click="toggleOpen"
        />
        <div
          v-if="isOpen"
          class="absolute bottom-full left-0 z-50 p-2 mb-1 w-72 max-w-[calc(100vw-2rem)] rounded-lg border shadow-lg bg-n-solid-2 border-n-weak"
        >
          <input
            v-model="query"
            type="search"
            autocomplete="off"
            class="px-2 py-1.5 w-full text-sm rounded-md border bg-n-solid-1 border-n-weak text-n-slate-12 placeholder:text-n-slate-10"
            :placeholder="$t('CONVERSATION.REPLYBOX.SHARE_SAVED_CONTACT_SEARCH')"
          />
          <div
            v-if="isSearching"
            class="px-1 py-2 text-xs text-n-slate-11"
          >
            {{ $t('CONVERSATION.REPLYBOX.SHARE_SAVED_CONTACT_SEARCHING') }}
          </div>
          <ul
            v-else-if="results.length"
            class="overflow-y-auto max-h-48 mt-1"
          >
            <li
              v-for="c in results"
              :key="c.id"
            >
              <button
                type="button"
                class="px-2 py-1.5 w-full text-xs text-left rounded-md text-n-slate-12 hover:bg-n-alpha-2"
                @click="addContact(c)"
              >
                {{ labelFor(c) }}
              </button>
            </li>
          </ul>
          <p
            v-else-if="query.trim().length >= 2"
            class="px-1 py-2 text-xs text-n-slate-11"
          >
            {{ $t('CONVERSATION.REPLYBOX.SHARE_SAVED_CONTACT_EMPTY') }}
          </p>
          <p
            v-else
            class="px-1 py-2 text-xs text-n-slate-11"
          >
            {{ $t('CONVERSATION.REPLYBOX.SHARE_SAVED_CONTACT_TYPE_MORE') }}
          </p>
        </div>
      </div>
    </OnClickOutside>
  </div>
</template>
