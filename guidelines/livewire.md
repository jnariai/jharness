# Livewire coding guidelines

<!-- harness-meta:start -->
The Livewire layer on top of `guidelines/laravel.md`. `/ai-context` appends it
after the Laravel guidelines in `docs/agents/coding_guidelines.md` when the target's
`composer.json` requires both `laravel/framework` and `livewire/livewire`.
`/jharness:update` refreshes a copy that was never edited. This block is stripped
from the copy.
<!-- harness-meta:end -->

Stack assumed: **Livewire 4+ single-file components** (`new class extends Component`
plus its template in one file), on top of the Laravel guidelines — every rule there
still applies. This part adds only what is specific to components.

---

## Golden rules

1. **A component is an entry point.** Authorize → validate with a Form object → one
   Action call → redirect or present. Nothing else.
2. **Components never write.** No `save()`, no `update()`, no transaction, no query
   chain. The Action owns the write and orchestrates it.
3. **Single-file components only.** The class and its template live in one file.
4. **Form objects hold shape.** The DTO's `fromForm()` turns validated input into VOs
   at the edge.
5. **Test components backend-first.** `Livewire::test()` drives the action and the
   test asserts the persisted state; UI assertions come on top.

---

## Layer map

| Layer | Path | Owns | Never |
|---|---|---|---|
| Livewire component | `resources/views/livewire/**` | UI state, authorize, validate, call Action | business rules, transactions, writes, query chains |
| Form object | `app/Livewire/Forms/*Form.php` | shape validation of input | business rules, persistence |

---

## Components

**Livewire 4+ single-file components.** One file under
`resources/views/livewire/`: a `<?php ?>` block declaring an anonymous class that
extends `Component`, followed by the template. No separate class file, no Volt
functional API.

```php
<?php

use App\Actions\Post\PublishPost;
use App\Livewire\Forms\PostForm;
use App\Models\Post;
use App\ValueObjects\PublishedAt;
use Livewire\Attributes\Computed;
use Livewire\Component;

new class extends Component {
    public Post $post;

    public PostForm $form;

    public function mount(Post $post): void
    {
        $this->post = $post;
        $this->form->setPost($post);
    }

    #[Computed]
    public function canPublish(): bool
    {
        return ! $this->post->isPublished();
    }

    public function publish(PublishPost $publish): void
    {
        $this->authorize('publish', $this->post);
        $this->form->validate();

        $publish->handle($this->post, PublishedAt::now());

        $this->redirectRoute('posts.show', $this->post);
    }
};

?>

<form wire:submit="publish">
    <label>
        {{ __('Title') }}
        <input type="text" wire:model="form.title">
        @error('form.title') <span class="error">{{ $message }}</span> @enderror
    </label>

    <button type="submit" @disabled(! $this->canPublish)>
        {{ __('Publish') }}
    </button>
</form>
```

Rules:

- **`new class extends Component` in the same file as its template.** The class
  block carries only state, `mount()`, computed properties and action methods.
- **Actions arrive as typed parameters of the action method**, not through `app()`
  or a constructor. The signature is the dependency list. When a method also takes
  arguments from the DOM (`wire:click="publish(5)"`), DOM arguments come first and
  injected services last.
- **One user intent = one public method = one Action call.** Two Action calls in one
  method means the missing concept is a third Action that orchestrates both.
- **`#[Computed]` for anything the view derives.** No queries in the template, no
  `@php` blocks.
- **A Form object for every write form** (`public PostForm $form;`). No loose public
  props for user input, and no inline `$this->validate([...])` rule arrays — the
  rules live on the Form object.
- **Read queries for the view go through model scopes or a read Action**, called
  from a `#[Computed]` method. Never a query builder chain in the component.
- **The component never opens a transaction** and never calls `save()`,
  `update()`, `create()` or `delete()`.
- **`wire:model` binds to `form.*`.** Bind to a plain public prop only for UI state
  (open tabs, filters, search terms).
- **Full-page components own the route**; nested components receive their data as
  parameters and stay presentational.
- **Templates carry no logic** beyond `@if`/`@foreach` over prepared data, and every
  user-facing string goes through `__()`.
- **`wire:submit` on the form element**, not a click handler on the button — the
  form is the intent.

---

## Form objects

A Form object is the component's FormRequest: shape rules and nothing else.

```php
namespace App\Livewire\Forms;

class PostForm extends Form
{
    #[Validate('required|string|max:120')]
    public string $title = '';

    #[Validate('required|string|min:10')]
    public string $body = '';

    #[Validate('nullable|date|after:now')]
    public ?string $scheduled_for = null;
}
```

- **Shape only** — required, max, min, date, email, unique. A rule that needs a DB
  lookup beyond `unique` is a business rule, and it lives in the Action.
- **The DTO converts it**, with a named constructor per source:

  ```php
  public static function fromForm(CustomerForm $form): self
  {
      return new self(
          name: $form->name,
          email: Email::fromString($form->email),
          document: Cpf::fromString($form->document),
          creditLimit: Money::fromCents((int) $form->credit_limit_cents, Currency::BRL),
      );
  }
  ```

  The component calls `$register->handle(RegisterCustomerData::fromForm($this->form))`
  and the Action never sees the form.

---

## Authorization in components

```php
public function publish(PublishPost $publish): void
{
    $this->authorize('publish', $this->post);
    // ...
}
```

- **Every action method authorizes first**, before validation — `mount()` checks do
  not cover later calls, since any public method can be invoked from the browser.
- Full-page components also carry route middleware (`auth`, `can:`), so an
  unauthenticated hit never reaches the component.
- `@can` in the template hides what the policy denies, but hiding is never the
  enforcement — the `authorize()` call is.

---

## Errors in components

Components carry no `try`/`catch` around Actions. The base `DomainException` holds
the shared `notify()` binding used in a Livewire request — a Flux toast when the
project uses Flux, otherwise a dispatched browser event — showing `userMessage()`.
One binding, one place to change it.

---

## Testing components

Components are tier-1 entry points: the Livewire test drives the user's action and
asserts what the backend did. UI assertions sit on top.

```php
it('publishes a draft post', function () {
    $author = User::factory()->create();
    $post = Post::factory()->draft()->for($author, 'author')->create();

    Livewire::actingAs($author)
        ->test('posts.edit', ['post' => $post])
        ->call('publish')
        ->assertHasNoErrors()
        ->assertRedirect(route('posts.show', $post));

    expect($post->refresh()->status)->toBe(PostStatus::Published);
});

it('requires a title', function () {
    $post = Post::factory()->draft()->create();

    Livewire::actingAs($post->author)
        ->test('posts.edit', ['post' => $post])
        ->set('form.title', '')
        ->call('publish')
        ->assertHasErrors(['form.title' => 'required']);
});

it('forbids publishing someone else\'s post', function () {
    Livewire::actingAs(User::factory()->create())
        ->test('posts.edit', ['post' => Post::factory()->draft()->create()])
        ->call('publish')
        ->assertForbidden();
});

it('hides the publish button once published', function () {
    $post = Post::factory()->published()->create();

    Livewire::actingAs($post->author)
        ->test('posts.edit', ['post' => $post])
        ->assertSeeHtml('disabled');
});
```

- **Backend first**: every action method gets a test asserting persisted state,
  dispatched events or the thrown domain exception, plus one for validation errors
  and one for authorization denied.
- **UI on top**: `assertSee`, `assertSeeHtml`, `assertSet`, `assertDispatched`, and
  browser tests for critical flows are all welcome — after the state assertion,
  never instead of it.

---

## Anti-patterns

| Do not | Do |
|---|---|
| business logic in a component method | Action called from the method |
| `$this->post->update([...])` in a component | the Action owns the write |
| a separate class file + view for a component | one single-file component |
| `$this->validate(['title' => 'required'])` inline | rules on the Form object |
| loose public props for form input | a Form object bound as `form.*` |
| `DB::transaction()` in a component | transaction inside the Action's `handle()` |
| query builder chains inside a component | scope, or read Action, from a `#[Computed]` |
| business rules in `#[Validate]` | Form = shape, Action = rules |
| `try`/`catch` around Actions in components | self-rendering domain exception |
| authorization only in `mount()` | `authorize()` in every action method |
| a component tested only with `assertSee` | assert state first, then the UI |

---

## Review checklist

- [ ] Components are single-file `new class extends Component`, methods thin.
- [ ] Every action method: authorize → validate the Form object → one Action → redirect.
- [ ] No writes, transactions or query chains in components.
- [ ] Form objects hold only shape rules; DTOs convert them with `fromForm()`.
- [ ] Every component action has a Livewire test asserting backend state, validation and authorization; UI assertions on top.
