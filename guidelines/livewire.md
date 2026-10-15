# Livewire coding guidelines

<!-- harness-meta:start -->
The Livewire layer on top of `guidelines/laravel.md`. `/ai-context` appends it
after the Laravel guidelines in `docs/agents/coding_guidelines.md` when the
target's `composer.json` requires both `laravel/framework` and `livewire/livewire`
and the project is not an Inertia app. `/jharness:update` refreshes a copy that was
never edited. This block is stripped from the copy.
<!-- harness-meta:end -->

Stack assumed: the **official Livewire starter kit on Livewire 4, without Flux** —
single-file components, Blade, Tailwind and Alpine. Every Laravel rule still applies;
this part adds only what is specific to components.

---

## Golden rules

1. **A component is an entry point.** Authorize → validate with a Form object → one
   Action call → redirect or present. Nothing else.
2. **Components never write.** No `save()`, no `update()`, no transaction, no query
   chain. The Action orchestrates the write; the model performs it.
3. **Single-file components only**, in Livewire 4's default locations, organized by
   context.
4. **Our own Blade components, no Flux.** UI primitives are anonymous Blade
   components with Tailwind and Alpine, owned by the project.
5. **Form objects hold shape.** The DTO's `fromForm()` turns validated input into VOs
   at the edge.
6. **Domain errors become a toast.** A shared trait catches domain exceptions in the
   component and dispatches one browser event; one Alpine toast renders it.
7. **Test components backend-first.** `Livewire::test()` drives the action and the
   test asserts the persisted state; UI assertions come on top.

---

## Layer map

| Layer | Path | Owns | Never |
|---|---|---|---|
| Full-page component | `resources/views/pages/<context>/<resource>/<page>.blade.php` | the route, UI state, authorize, validate, call one Action | business rules, transactions, writes, query chains |
| Nested component | `resources/views/components/<context>/<name>.blade.php` | an interactive piece of a page, same contract | owning a route |
| Form object | `app/Livewire/Forms/<Context>/*Form.php` | shape validation of input | business rules, persistence |
| Component concern | `app/Livewire/Concerns/*.php` | cross-cutting component behavior (domain-error toast) | domain logic |
| UI primitive | `resources/views/components/ui/*.blade.php` | markup + Tailwind + Alpine for buttons, inputs, modals, toast | server calls, domain names |
| Layout | `resources/views/layouts/` | shell, navigation, toast outlet | page data |

---

## Components

**Livewire 4 single-file components.** One file: a `<?php ?>` block declaring an
anonymous class that extends `Component`, followed by the template.

```php
<?php

use App\Actions\Blog\PublishPost;
use App\Livewire\Concerns\HandlesDomainErrors;
use App\Livewire\Forms\Blog\PostForm;
use App\Models\Post;
use App\ValueObjects\PublishedAt;
use Livewire\Attributes\Locked;
use Livewire\Component;

new class extends Component {
    use HandlesDomainErrors;

    #[Locked]
    public Post $post;

    public PostForm $form;

    public function mount(Post $post): void
    {
        $this->authorize('update', $post);

        $this->post = $post;
        $this->form->fillFrom($post);
    }

    public function publish(PublishPost $publish): void
    {
        $this->authorize('publish', $this->post);
        $this->form->validate();

        $publish->handle($this->post, PublishedAt::now());

        session()->flash('success', __('Post published.'));
        $this->redirectRoute('posts.show', $this->post, navigate: true);
    }
};

?>

<form wire:submit="publish" class="space-y-4">
    <x-ui.input wire:model="form.title" name="form.title" :label="__('Title')" />

    @can('publish', $post)
        <x-ui.button type="submit">{{ __('Publish') }}</x-ui.button>
    @endcan
</form>
```

Rules:

- **Full-page components live in `resources/views/pages/<context>/…`** and are
  routed with `Route::livewire()`; **nested components in
  `resources/views/components/<context>/…`**. The context folders mirror the
  backend.
- **The class block carries only** state, `mount()`, `boot()`, computed properties
  and action methods.
- **Actions arrive as typed parameters of the action method.** DOM arguments come
  first, injected services last.
- **One user intent = one public method = one Action call.**
- **`#[Locked]` on every public property the browser must not change** — models,
  ids, anything set in `mount()`.
- **Models in public properties are allowed**, `#[Locked]`. Livewire's checksummed
  snapshot carries the model's key; everything the component *renders*, every URL
  and every dispatched event uses `public_id`.
- **Reads for the view go through `#[Computed]` methods calling a `Get*` Action**,
  injected in `boot()` (computed methods take no injected parameters). Never a query
  chain in the component.

  ```php
  protected GetOverdueInvoices $getOverdue;

  #[Url]
  public string $search = '';

  public function boot(GetOverdueInvoices $getOverdue): void
  {
      $this->getOverdue = $getOverdue;
  }

  #[Computed]
  public function invoices(): LengthAwarePaginator
  {
      return $this->getOverdue->handle(new GetOverdueInvoicesFilter(
          pagination: Pagination::default(),
          search: $this->search ?: null,
      ));
  }
  ```

- **Filters, search and the page live in the query string** (`#[Url]`,
  `WithPagination`) — plain public props are for UI state only.
- **Heavy sections load lazily**: `#[Lazy]` on a nested component, or a Livewire 4
  island around the slow part of a template, with a placeholder.
- **Navigation uses `wire:navigate`** and `navigate: true` on redirects.
- **The component never opens a transaction** and never calls `save()`,
  `update()`, `create()` or `delete()`.

---

## Templates and UI components

- **Templates carry no logic** beyond `@if`/`@foreach` over prepared data and `@can`.
  No queries, no `@php` blocks.
- **Every user-facing string goes through `__()`.**
- **UI primitives are anonymous Blade components** in `resources/views/components/ui/`
  — `x-ui.button`, `x-ui.input`, `x-ui.select`, `x-ui.modal`, `x-ui.toast`,
  `x-ui.table` — built with Tailwind, behavior in Alpine (`x-data`), props declared
  with `@props`. They forward attributes (`$attributes->merge(...)`) so `wire:model`
  and `wire:click` pass through.
- **Primitives stay generic**: no domain names, no server calls. Domain pieces are
  nested Livewire components or Blade components under a context folder.
- **`x-ui.input` renders its own label and `@error`** for the `name` it receives, so
  forms never repeat error plumbing.
- **Alpine for client-only behavior** (dropdowns, tabs, copy-to-clipboard) — never
  for data that belongs to the server.
- **`wire:submit` on the form element**, not a click handler on the button.
- **Abilities in templates are `@can`** — global abilities (`@can('viewBilling')`)
  and record abilities (`@can('refund', $invoice)`). Hiding is never the
  enforcement; `authorize()` in the action method is.

---

## Form objects

A Form object is the component's FormRequest: shape rules and nothing else.

```php
namespace App\Livewire\Forms\Blog;

class PostForm extends Form
{
    #[Validate('required|string|max:120')]
    public string $title = '';

    #[Validate('required|string|min:10')]
    public string $body = '';

    public function fillFrom(Post $post): void
    {
        $this->title = $post->title;
        $this->body = $post->body;
    }
}
```

- **A Form object for every write**, bound as `form.*`. No loose public props for
  user input, no inline `$this->validate([...])`.
- **Shape only** — required, max, min, date, email, unique.
- **The DTO converts it**: `CreatePostData::fromForm($this->form)`. The Action never
  sees the form.

---

## Authorization in components

- **Every action method authorizes first**, before validation — `mount()` checks do
  not cover later calls, since any public method can be invoked from the browser.
- `mount()` authorizes viewing; full-page routes also carry middleware (`auth`,
  `can:`).
- **The component is the only place the policy runs.** The Action never authorizes.

---

## Errors in components

Domain exceptions are handled once, by a trait every component that calls an
Action uses, through Livewire's `exception()` hook:

```php
namespace App\Livewire\Concerns;

trait HandlesDomainErrors
{
    public function exception(Throwable $e, callable $stopPropagation): void
    {
        if (! $e instanceof DomainException) {
            return;
        }

        $this->dispatch('toast', type: 'error', message: $e->userMessage());
        $stopPropagation();
    }
}
```

```blade
{{-- resources/views/components/ui/toast.blade.php, rendered once in the layout --}}
<div
    x-data="{
        toasts: [],
        add(toast) {
            toast.id = Date.now() + Math.random();
            this.toasts.push(toast);
            if (toast.type !== 'error') setTimeout(() => this.remove(toast.id), 5000);
        },
        remove(id) {
            this.toasts = this.toasts.filter((t) => t.id !== id);
        },
    }"
    x-on:toast.window="add($event.detail)"
    x-init="@if (session('success')) add({ type: 'success', message: @js(session('success')) }) @endif"
    role="status"
    aria-live="polite"
    class="fixed bottom-4 right-4 space-y-2"
>
    <template x-for="toast in toasts" :key="toast.id">
        <div :class="toast.type === 'error' ? 'bg-red-600' : 'bg-green-600'" class="flex items-start gap-3 rounded px-4 py-2 text-white">
            <span x-text="toast.message"></span>
            <button type="button" x-on:click="remove(toast.id)" aria-label="{{ __('Dismiss') }}">&times;</button>
        </div>
    </template>
</div>
```

- **The toast outlet is a live region** — `role="status"` and `aria-live="polite"`
  on the container, which stays in the layout so it exists before any message
  arrives. Messages are announced without moving focus.
- **Success toasts close after 5 seconds; error toasts stay until dismissed.** Every
  toast has a dismiss button, so nobody has to read an error against a timer.

- **No `try`/`catch` around Actions** in component methods.
- **Success messages**: a session `success` flash before a redirect, or
  `$this->dispatch('toast', type: 'success', message: …)` when staying on the page.
- **Components never `abort()`.** Authorization failures come from
  `$this->authorize()`; everything else is a domain exception.
- Validation errors render inline through `x-ui.input`; they never become toasts.

---

## Testing components

Components are tier-1 entry points: the Livewire test drives the user's action and
asserts what the backend did.

```php
it('publishes a draft post', function () {
    $author = User::factory()->create();
    $post = Post::factory()->draft()->for($author, 'author')->create();

    Livewire::actingAs($author)
        ->test('pages::blog.posts.edit', ['post' => $post])
        ->call('publish')
        ->assertHasNoErrors()
        ->assertRedirect(route('posts.show', $post));

    expect($post->refresh()->status)->toBe(PostStatus::Published);
});

it('turns a domain error into a toast', function () {
    $post = Post::factory()->published()->create();

    Livewire::actingAs($post->author)
        ->test('pages::blog.posts.edit', ['post' => $post])
        ->call('publish')
        ->assertDispatched('toast', type: 'error');

    expect($post->refresh()->status)->toBe(PostStatus::Published);
});

it('forbids publishing someone else\'s post', function () {
    Livewire::actingAs(User::factory()->create())
        ->test('pages::blog.posts.edit', ['post' => Post::factory()->draft()->create()])
        ->assertForbidden();
});
```

- **Backend first**: every action method gets a test asserting persisted state,
  dispatched events or the toast for a domain exception, plus one for validation
  errors and one for authorization denied.
- **UI on top**: `assertSee`, `assertSet`, browser tests for critical flows — after
  the state assertion, never instead of it.

---

## Tooling

- `npm run build` is a gate (Tailwind + Alpine bundle).
- Arch additions to `tests/Arch.php`:

  ```php
  arch('form objects hold shape only')
      ->expect('App\Livewire\Forms')
      ->not->toUse(['Illuminate\Support\Facades\DB', 'App\Actions']);
  ```

- `scripts/grep-gates.sh` (see the Laravel *Tooling and enforcement* section)
  runs its Livewire block automatically when `composer.json` requires
  `livewire/livewire`: no writes, transactions or queries in components, no `@php`
  in templates, no `<flux:` anywhere in `resources/views`.

---

## Anti-patterns

| Do not | Do |
|---|---|
| business logic in a component method | Action called from the method |
| `$this->post->update([...])` in a component | the Action orders the write, the model performs it |
| a separate class file + view | one single-file component |
| components in `resources/views/livewire/` | `pages/<context>/` and `components/<context>/` |
| Flux components | `x-ui.*` Blade components + Tailwind + Alpine |
| domain names inside `components/ui/` | a context component wrapping the primitive |
| `$this->validate(['title' => 'required'])` inline | rules on the Form object |
| loose public props for form input | a Form object bound as `form.*` |
| a public model or id without `#[Locked]` | `#[Locked]` |
| rendering `$post->id` in a template or URL | `$post->public_id` / route binding |
| `Invoice::query()->…` in a `#[Computed]` | a `Get*` Action injected in `boot()` |
| `DB::transaction()` in a component | transaction inside the Action |
| `try`/`catch` around Actions | `HandlesDomainErrors` + the toast |
| `abort(403)` in a component method | `$this->authorize(...)` |
| authorization only in `mount()` | `authorize()` in every action method |
| `@php` blocks or queries in templates | `#[Computed]` properties |
| a component tested only with `assertSee` | assert state first, then the UI |

---

## Review checklist

- [ ] Single-file components in `resources/views/pages/<context>/` or `components/<context>/`.
- [ ] Every action method: authorize → validate the Form object → one Action → redirect or toast.
- [ ] `#[Locked]` on models and ids; templates and URLs use `public_id`.
- [ ] Reads through `#[Computed]` + a `Get*` Action injected in `boot()`; filters in `#[Url]`.
- [ ] No writes, transactions or query chains in components; no `@php` in templates.
- [ ] UI from `x-ui.*` Blade components; no Flux.
- [ ] `HandlesDomainErrors` on every component that calls an Action; one toast in the layout, a polite live region; error toasts stay until dismissed.
- [ ] Every component action has a Livewire test asserting backend state, validation and authorization; UI on top.
