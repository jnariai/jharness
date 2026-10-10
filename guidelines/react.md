# React coding guidelines

<!-- harness-meta:start -->
The React layer on top of `guidelines/laravel.md` + `guidelines/inertia.md`.
`/ai-context` appends it when the target's `package.json` requires
`@inertiajs/react`. `/jharness:update` refreshes a copy that was never edited.
This block is stripped from the copy.
<!-- harness-meta:end -->

Stack assumed: the **official React starter kit** — React 19, TypeScript, Inertia 3,
Tailwind, shadcn/ui, Wayfinder. Every Laravel and Inertia rule still applies; this
part adds only what is specific to React.

---

## Golden rules

1. **Function components and hooks only.** No class components.
2. **Props are typed from the generated types.** A page's props are
   `App.Data.<Context>.*View` types, never a hand-written interface.
3. **No data fetching in React.** No `useEffect` that loads server data, no
   `fetch`/`axios` to your own backend, no React Query/SWR. Inertia props are the data.
4. **Components present; pages compose.** Rules, permissions and labels arrive from
   the server.
5. **Follow the kit's conventions** — file names, folder names, `@/` alias, shadcn
   primitives — so kit updates and new pages look the same.

---

## Pages

```tsx
import { Form, Head } from '@inertiajs/react';
import { store as refundInvoice } from '@/actions/App/Http/Controllers/Billing/RefundInvoiceController';
import { InvoiceTable } from '@/components/billing/invoice-table';
import { Button } from '@/components/ui/button';
import AppLayout from '@/layouts/app-layout';
import { useTranslations } from '@/hooks/use-translations';
import type { Paginated } from '@/types';

type Props = {
    invoices: Paginated<App.Data.Billing.InvoiceRowView>;
    filters: App.Data.Billing.InvoiceFiltersView;
};

export default function Index({ invoices, filters }: Props) {
    const { t } = useTranslations();

    return (
        <AppLayout>
            <Head title={t('Invoices')} />

            <InvoiceTable
                invoices={invoices}
                filters={filters}
                renderActions={(invoice) =>
                    invoice.can.refund && (
                        <Form {...refundInvoice.form(invoice.id)}>
                            {({ processing }) => (
                                <Button type="submit" variant="outline" disabled={processing}>
                                    {t('Refund')}
                                </Button>
                            )}
                        </Form>
                    )
                }
            />
        </AppLayout>
    );
}
```

- **One file per Inertia component name**: `pages/billing/invoices/index.tsx` for
  `billing/invoices/index`. File and folder names are `kebab-case`, as in the kit.
- **Default export for pages**, named exports for everything else.
- **Props typed with a local `Props` type** built from generated types and
  `Paginated<T>`.
- **The layout wraps the page** (or is set as a persistent layout the way the kit
  does it); the toast outlet lives in the layout.
- **Shared props** come from `usePage().props`, typed once through `InertiaConfig`
  — `auth.can`, `locale` — wrapped in small hooks (`useAbilities()`) rather than
  read raw in every component.
- **`Page.layout` is an array or a function declaration**
  (`Index.layout = [AppLayout]`); an arrow function assigned to `.layout` no longer
  works in Inertia 3.

---

## Components

- **`components/<context>/` for domain components**, `components/ui/` for shadcn
  primitives, `components/` root for app-wide pieces. File names `kebab-case`,
  component names `PascalCase`.
- **Props are explicit and typed**; pass the View DTO (or the fields it needs), not
  the whole page props.
- **Local state with `useState`** for UI only — dialog open, selected tab, an input
  before submit.
- **`useEffect` is for synchronizing with the outside world** (focus, a third-party
  widget, a subscription) — never for loading data, deriving state from props, or
  reacting to a prop change. Derive during render instead.
- **No premature memoization.** `useMemo`/`useCallback`/`memo` only with a measured
  reason (the React Compiler, when enabled by the kit, handles the rest).
- **Custom hooks live in `resources/js/hooks/`**, named `use-*.ts`, and hold UI
  behavior only — `useAbilities`, `useFlashToast`, `useMoney`.
- **shadcn primitives stay generic.** Wrap them in a context component for domain
  meaning; do not add domain props to `components/ui/*`.
- **Accessibility comes with the primitives** — keep labels on inputs, `aria-*` on
  icon buttons, and use `<Button type="submit">` inside forms.

---

## Forms

```tsx
<Form {...InvoiceController.store.form()} resetOnSuccess>
    {({ errors, processing }) => (
        <>
            <Label htmlFor="number">{t('Number')}</Label>
            <Input id="number" name="number" required />
            <InputError message={errors.number} />

            <Button type="submit" disabled={processing}>
                {t('Create invoice')}
            </Button>
        </>
    )}
</Form>
```

- **`<Form>` + Wayfinder `.form()`** for plain submits; uncontrolled inputs with
  `name` matching the FormRequest key.
- **`useForm` for real client state** — dynamic rows, multi-step, a long-lived
  draft — submitting with `form.submit(InvoiceController.store())`.
- **`InputError` (kit component) under each field**; no custom error plumbing.
- **Confirmation dialogs wrap the `<Form>`**; they never call the server
  themselves.

---

## Flash and toasts

One `FlashToaster` component in the app layout subscribes to the router's `flash`
event (`router.on('flash', …)` in a `useEffect`, unsubscribing on unmount) and
shows `flash.success` / `flash.error` with the kit's toast primitive (sonner).
Pages never render domain errors themselves.

---

## Formatting and translations

- **`lib/format.ts`** holds pure formatters: `formatMoney(money: App.ValueObjects.Money)`,
  `formatDate(iso: string)`, using `Intl` with the shared `locale`.
- **`t()` from `useTranslations()`** — a thin hook in `hooks/` over the i18n helper —
  for every string a page owns; server strings arrive translated.

---

## Anti-patterns

| Do not | Do |
|---|---|
| class components | function components + hooks |
| `useEffect(() => { fetch(...) }, [])` | an Inertia prop, deferred prop or partial reload |
| React Query, SWR, Redux, Zustand | Inertia props + `useState` for UI |
| `useEffect` copying props into state | derive during render |
| `interface Invoice { … }` for server data | `App.Data.Billing.InvoiceRowView` |
| `user.role === 'admin'` | `useAbilities().manageUsers`, `invoice.can.refund` |
| domain props added to `components/ui/button.tsx` | a context component wrapping it |
| `<a href={'/invoices/' + id}>` | `<Link href={InvoiceController.show(invoice.id)}>` |
| `onClick={() => router.post('/invoices/…')}` | `<Form {...refundInvoice.form(invoice.id)}>` |
| `useMemo` everywhere | measure first |
| hardcoded strings | `t('…')` |

---

## Review checklist

- [ ] Pages in `pages/<context>/<resource>/<page>.tsx`, default export, `Props` typed from generated types.
- [ ] No server data loaded in effects; no client store.
- [ ] Forms use `<Form>` + Wayfinder; `useForm` only for real client state.
- [ ] Abilities from `auth.can` / `can` fields; no role checks.
- [ ] shadcn primitives untouched by domain concerns.
- [ ] Every string through `t()`; money and dates through `lib/format.ts`.
- [ ] `npm run types`, `lint`, `format:check` pass.
