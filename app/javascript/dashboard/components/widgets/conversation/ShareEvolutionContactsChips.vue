<script setup>
defineProps({
  contacts: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['remove']);

function labelFor(contact) {
  const phone = contact.phoneNumber || '';
  return phone ? `${contact.name} (${phone})` : contact.name;
}
</script>

<template>
  <div
    v-if="contacts.length"
    class="flex flex-wrap gap-1.5 px-3 pb-1"
  >
    <div
      v-for="c in contacts"
      :key="c.id"
      class="inline-flex gap-1 items-center px-2 py-0.5 max-w-full text-xs rounded-md bg-n-alpha-2 text-n-slate-12"
    >
      <span class="truncate">{{ labelFor(c) }}</span>
      <button
        type="button"
        class="flex-shrink-0 text-n-slate-11 hover:text-n-slate-12"
        :aria-label="$t('CONVERSATION.REPLYBOX.SHARE_SAVED_CONTACTS_REMOVE')"
        @click="emit('remove', c.id)"
      >
        <span class="i-lucide-x size-3.5" />
      </button>
    </div>
  </div>
</template>
