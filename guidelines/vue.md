# Vue coding guidelines

<!-- harness-meta:start -->
The Vue layer on top of `guidelines/laravel.md` + `guidelines/inertia.md`.
`/ai-context` appends it when the target's `package.json` requires
`@inertiajs/vue3`. `/jharness:update` refreshes a copy that was never edited.
This block is stripped from the copy.
<!-- harness-meta:end -->

Stack assumed: the **official Vue starter kit** — Vue 3, TypeScript, Inertia 3,
Tailwind, shadcn-vue, Wayfinder. Every Laravel and Inertia rule still applies; this
part adds only what is specific to Vue.

---

## Golden rules

1. **`<script setup lang="ts">` and the Composition API only.** No Options API.
2. **Props are typed from the generated types** with `defineProps<Props>()`, never
   a hand-written interface for server data.
3. **No data fetching in Vue.** No `onMounted` loading server data, no `fetch`/`axios`
   to your own backend. Inertia props are the data.
4. **Components present; pages compose.** Rules, permissions and labels arrive from
   the server.
5. **Follow the kit's conventions** — file names, folder names, `@/` alias,
   shadcn-vue primitives.

---

## Pages

```vue
<script setup lang="ts">
import { Form, Head } from '@inertiajs/vue3';
import { store as refundInvoice } from '@/actions/App/Http/Controllers/Billing/RefundInvoiceController';
import InvoiceTable from '@/components/billing/InvoiceTable.vue';
import { Button } from '@/components/ui/button';
import AppLayout from '@/layouts/AppLayout.vue';
import type { Paginated } from '@/types';

defineProps<{
    invoices: Paginated<App.Data.Billing.InvoiceRowView>;
    filters: App.Data.Billing.InvoiceFiltersView;
}>();
</script>

<template>
    <AppLayout>
        <Head :title="$t('Invoices')" />

        <InvoiceTable :invoices="invoices" :filters="filters">
            <template #actions="{ invoice }">
                <Form
                    v-if="invoice.can.refund"
                    v-bind="refundInvoice.form(invoice.id)"
                    #default="{ processing }"
                >
                    <Button type="submit" variant="outline" :disabled="processing">
                        {{ $t('Refund') }}
                    </Button>
                </Form>
            </template>
        </InvoiceTable>
    </AppLayout>
</template>
```

- **One file per Inertia component name**, following the kit's casing:
  `pages/billing/invoices/Index.vue` for `billing/invoices/Index` — the component
  name passed to `Inertia::render()` matches the file exactly.
- **`defineProps<…>()` with generated types** and `Paginated<T>`.
- **The layout wraps the page** (or is the kit's persistent layout); the toast
  outlet lives in the layout.
- **Shared props** come from `usePage().props`, typed once through `InertiaConfig`,
  wrapped in small composables (`useAbilities()`).

---

## Components

- **`components/<context>/` for domain components**, `components/ui/` for
  shadcn-vue primitives. Component files `PascalCase.vue`, as in the kit.
- **Props and emits typed**: `defineProps<…>()`, `defineEmits<…>()`. Slots for
  composition (`#actions`) instead of passing render functions or flags.
- **Local state with `ref`/`reactive`** for UI only.
- **`computed` derives**, `watch` synchronizes with the outside world — never a
  `watch` that copies a prop into local state or loads data.
- **Composables live in `resources/js/composables/`**, named `use*.ts`, UI behavior
  only — `useAbilities`, `useFlashToast`, `useMoney`.
- **shadcn-vue primitives stay generic**; wrap them for domain meaning.
- **No `v-html`** with anything that came from a user.

---

## Forms

```vue
<Form v-bind="InvoiceController.store.form()" reset-on-success #default="{ errors, processing }">
    <Label for="number">{{ $t('Number') }}</Label>
    <Input id="number" name="number" required />
    <InputError :message="errors.number" />

    <Button type="submit" :disabled="processing">{{ $t('Create invoice') }}</Button>
</Form>
```

- **`<Form>` + Wayfinder `.form()`** for plain submits, inputs named after the
  FormRequest keys.
- **`useForm` for real client state**, submitting with
  `form.submit(InvoiceController.store())`.
- **`InputError` under each field.** Confirmation dialogs wrap the `<Form>`.

---

## Flash and toasts

One `FlashToaster.vue` in the app layout subscribes to the router's `flash` event
(`router.on('flash', …)` in `onMounted`, removed in `onUnmounted`) and shows
`flash.success` / `flash.error` with the kit's toast primitive. Pages never render domain
errors themselves.

---

## Formatting and translations

- **`lib/format.ts`** holds pure formatters (`formatMoney`, `formatDate`) using
  `Intl` with the shared `locale`.
- **`$t()` / `trans()` from the i18n plugin** for every string a page owns.

---

## Anti-patterns

| Do not | Do |
|---|---|
| Options API, `export default { data() {} }` | `<script setup lang="ts">` |
| `onMounted(async () => fetch(...))` | an Inertia prop, deferred prop or partial reload |
| Pinia or a global reactive store | Inertia props + `ref` for UI |
| `watch(() => props.x, v => local.value = v)` | `computed` |
| `interface Invoice { … }` for server data | `App.Data.Billing.InvoiceRowView` |
| `v-if="user.role === 'admin'"` | `abilities.manageUsers`, `invoice.can.refund` |
| `:href="'/invoices/' + id"` | `InvoiceController.show(invoice.id)` |
| `router.post('/invoices/…')` on click | `<Form v-bind="….form(invoice.id)">` |
| `v-html` with user content | text interpolation |
| hardcoded strings | `$t('…')` |

---

## Review checklist

- [ ] Pages in `pages/<context>/<resource>/<Page>.vue`, `<script setup lang="ts">`, props from generated types.
- [ ] No server data loaded in hooks; no Pinia.
- [ ] Forms use `<Form>` + Wayfinder; `useForm` only for real client state.
- [ ] Abilities from `auth.can` / `can` fields; no role checks.
- [ ] Every string through `$t()`; money and dates through `lib/format.ts`.
- [ ] `npm run types` (`vue-tsc`), `lint`, `format:check` pass.
