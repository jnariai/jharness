# Laravel + Livewire coding guidelines

<!-- harness-meta:start -->
Drop this into a Laravel project as `docs/agents/coding_guidelines.md`. It is the
convention layer agents must follow when writing code in that project: `/plan`
decomposes against it, `ralph.sh` sessions read it before the first edit.
`/ai-context` copies it there automatically when the target is a Laravel +
Livewire repo and the file is absent; this block is stripped from the copy.

> Keep it hand-written there — without the `/ai-context` banner on line 3 the
> generator never clobbers it. Do not run `/ai-context --adopt` on this file.
<!-- harness-meta:end -->

Stack assumed: Laravel 12+, **Livewire 4+ single-file components**
(`new class extends Component` plus its template in one file), Pest,
PHP 8.2+ (readonly classes, backed enums, `final` by default).

---

## Golden rules

1. **Actions own writes.** Every state change goes through an Action class with a
   `handle()` method that opens the transaction.
2. **Models are rich domain bags that persist themselves — domain rules only.**
   The entity guards its own invariants and its own state machine, and saves. The
   Action still owns the transaction, and owns every business rule.
3. **Value objects carry their own validity.** A `Money` that exists is a valid
   `Money`. Invalid input never becomes a VO.
4. **Actions speak DTOs and VOs, in and out.** Every argument and every return is a
   model, a VO or a DTO. Never an array, never loose primitives, never `bool`.
5. **Enums are always string-backed, and they own every rule.** A lookup table is
   storage — an `id` and a `label` behind a foreign key. Never logic.
6. **Entry points validate, authorize, delegate.** Controllers, console commands
   and Livewire components do those three things and nothing else.
7. **Jobs and listeners own only their own plumbing.** Retries, backoff, uniqueness,
   overlap — then one Action call.
8. **Every external call goes through a Gateway.** A Client transports, a Gateway
   translates; more than one vendor means a contract plus adapters.
9. **Form objects are FormRequests.** Shape only — required, max, unique, format.
   Never a business rule.
10. **Domain exceptions render themselves.** No error plumbing in components.
11. **Reads are Eloquent + scopes, composed in an Action.** `#[Scope]` attributes are
    the vocabulary, raw `where` is banned, and a report gets an Action of its own.
12. **Everything `final`, everything typed.** No `mixed`, no untyped properties, no
    array-shaped payloads where a VO or enum fits.

---

## Layer map

| Layer | Path | Owns | Never |
|---|---|---|---|
| Livewire component | `resources/views/livewire/**` | UI state, authorize, validate, call Action | business rules, transactions, write queries |
| Controller | `app/Http/Controllers/*.php` | authorize + validate (via FormRequest), call Action, respond | business rules, queries, transactions |
| Console command | `app/Console/Commands/*.php` | validate options, call Action, report | business rules, queries, transactions |
| Form object / FormRequest | `app/Livewire/Forms/*Form.php`, `app/Http/Requests/*Request.php` | shape validation of input, authorization | business rules, persistence |
| Job | `app/Jobs/*.php` | retries, backoff, timeout, uniqueness, overlap, `failed()` — then one Action call | validation, authorization, business rules |
| Listener | `app/Listeners/*.php` | queue config for the reaction — then one Action call | validation, authorization, business rules |
| Action | `app/Actions/<Aggregate>/*.php` | business rules, orchestration, transaction boundary, composing reads from scopes, reports | HTTP/UI concerns, validation of shape, raw `where`, re-checking model invariants |
| Model | `app/Models/*.php` | domain rules: its own invariants, state transitions, relations, casts, `#[Scope]` predicates, enum ⇄ lookup id mapping | business rules, cross-aggregate orchestration, events, config, static finders |
| Value object | `app/ValueObjects/*.php` | its own validity + behavior | persistence, container access |
| DTO | `app/Data/*Data.php` | typed transport across an Action boundary | rules, behavior, persistence |
| Gateway | `app/Gateways/<Vendor>/*Gateway.php` | domain ⇄ vendor translation, vendor errors → domain exceptions | HTTP mechanics, retries, headers |
| Client | `app/Gateways/<Vendor>/*Client.php` | transport: base URL, auth, headers, timeout, transport retries | domain knowledge, business rules |
| Contract | `app/Contracts/*.php` | the domain-shaped interface a vendor must satisfy | vendor vocabulary |
| Enum | `app/Enums/*.php` | closed sets, transition tables, labels, every rule about the value | queries, reading its own lookup table |
| Lookup table | `<name>_status`, `<name>_type`, … | `id` + `label`, referenced by FK | behavior, rules, an Eloquent model |
| Cast | `app/Casts/*.php` | VO ⇄ column mapping | rules of any kind |
| Policy | `app/Policies/*.php` | authorization | state changes |
| Exception | `app/Exceptions/*.php` | domain failure + how it is shown | control flow for expected branches |

Layout is plain Laravel: grouped by type under `app/`, one subfolder per
aggregate inside `Actions/`. No `Domain/`, no `src/Modules/`.

---

## Actions

One class, one intent. `handle()` is the only public entry point, and it opens
the transaction.

```php
namespace App\Actions\Post;

final class PublishPost
{
    public function __construct(
        private readonly Dispatcher $events,
    ) {}

    public function handle(Post $post, PublishedAt $at): Post
    {
        return DB::transaction(function () use ($post, $at) {
            $post->publish($at);                       // model enforces + persists
            $post->author->increment('published_count');
            $this->events->dispatch(new PostPublished($post));

            return $post;
        });
    }
}
```

Rules:

- **Name it after the intent**: verb + noun. `PublishPost`, `CancelSubscription`,
  `RefundInvoice`. Never `PostService`, never `PostManager`.
- **`handle()` always**, even for a one-liner. Uniform entry point means the class
  can move to a job, a command, or a queue without a rename.
- **`DB::transaction()` wraps the whole body of a write Action**, including
  single-write ones. Consistency beats micro-optimizing one query.
- **Dependencies via constructor injection**, typed and `readonly`.
- **The Action is the source of business rules and the orchestrator.** Anything
  that depends on the use case — other aggregates, config, quotas, the actor, time
  policies, the order effects run in, what else must change — is decided here, and
  a job or a console command calling the same Action inherits it.
- **Never re-check a model invariant.** If the model already refuses the transition,
  the Action lets it throw. Duplicating the guard puts the same rule in two places
  that will drift.
- **In and out are DTOs, VOs or models — never primitives, never arrays.**
  `handle(Post $post, PublishedAt $at): Post`, not
  `handle(int $postId, string $date): array`. Route model binding and VO factories
  do the conversion at the edge; see *Action boundaries*.
- **More than two or three scalars collapse into one DTO.** A growing argument list
  is a missing input object, not a longer signature.
- **Return the thing the caller needs** — the affected model, a VO, or a result
  DTO. Never `bool`, never `void` when there is something to return, never an
  associative array.
- **No `request()`, no `auth()`, no session** inside an Action. Actor and input
  arrive as arguments.

### Reads

There is no repository layer and no query-object layer. The query language is
**Eloquent: rich domain + active record + the builder.** Reads come in two shapes,
and the difference is what the query is *for*, not how long it is.

**1 — Ordinary reads: the Action composes the builder from scopes.**

The Action calls `Model::query()` and chains **scopes**, which are the domain's
vocabulary for predicates. It reads like the business sentence it implements.

```php
final class SendOverdueReminders
{
    public function handle(Tenant $tenant, Reminder $reminder): int
    {
        $invoices = Invoice::query()
            ->forTenant($tenant)
            ->overdue()
            ->withoutReminderSince($reminder->cooldown())
            ->with('customer')
            ->get();

        // ...
    }
}
```

- **Every predicate is a scope**, declared with the `#[Scope]` attribute on the
  model (see Models). A bare `->where('status_id', 3)` in an Action means a scope
  is missing.
- **No raw `where`.** `whereRaw`, `havingRaw`, string conditions and interpolated
  SQL are out. The builder covers it: `whereBelongsTo`, `whereRelation`,
  `whereHas`, `whereIn`, `whereBetween`, `whereNull`, `when()`.
- **Eager load explicitly** (`with()`); never rely on lazy loading in an Action.
- The Action still returns models or VOs — never a `Builder`. Handing a builder to
  a caller leaks the query out of the layer that owns it.

**2 — Reports and specific reads: wrapped in their own Action.**

When the query stops being a filtered list of an aggregate — a report, a cross-table
aggregate, a grouped total, a derived column, a projection into a shape that is not
a model — it gets an Action of its own, named after what it answers.

```php
final class MonthlyRevenueByRegion
{
    public function handle(Period $period): Collection
    {
        return Invoice::query()
            ->issuedWithin($period)                              // scope, not whereRaw
            ->selectRaw('region_id, SUM(total_cents) AS revenue_cents')
            ->groupBy('region_id')
            ->get()
            ->map(fn (object $row) => new RegionRevenue(
                RegionId::from($row->region_id),
                Money::fromCents($row->revenue_cents, Currency::BRL),
            ));
    }
}
```

- **A raw expression is allowed only here**, and only for what the builder cannot
  express — aggregates, window functions, database-specific projections. Filtering
  still goes through scopes, and every value is a binding, never interpolation.
- **Name it after the answer**, not the query: `MonthlyRevenueByRegion`,
  `TopCustomersByLifetimeValue`. Never `InvoiceReportAction`.
- **Return VOs or dedicated read objects**, not `stdClass` rows and not arrays.
- One report Action per report. Do not add `$groupBy` flags to make one class serve
  five reports.

A read Action has no `DB::transaction()`. That absence is the signal it is a read.

---

## Models

**Rich domain bag + active record.** The model carries the entity's own vocabulary
and its own consistency, and it persists itself. It carries **domain rules only** —
business rules belong to the Action.

```php
use Illuminate\Database\Eloquent\Attributes\Scope;

final class Post extends Model
{
    protected function casts(): array
    {
        return [
            'published_at' => PublishedAtCast::class,
        ];
    }

    public function publish(PublishedAt $at): void
    {
        throw_if($this->isPublished(), new AlreadyPublished($this->id));
        throw_if($this->body === '', new CannotPublishEmptyPost($this->id));

        $this->update([
            'status'       => PostStatus::Published,   // mutator writes post_status_id
            'published_at' => $at,
        ]);
    }

    public function isPublished(): bool
    {
        return $this->status === PostStatus::Published;
    }

    // enum <-> lookup row; see "Enums and lookup tables"
    protected function status(): Attribute
    {
        return Attribute::make(
            get: fn (mixed $value, array $attributes): PostStatus => PostStatus::from(
                DB::table('post_status')
                    ->where('id', $attributes['post_status_id'])
                    ->value('label'),
            ),
            set: fn (PostStatus $status): array => [
                'post_status_id' => self::statusId($status),
            ],
        );
    }

    #[Scope]
    protected function published(Builder $query): void
    {
        $query->where('post_status_id', self::statusId(PostStatus::Published));
    }

    #[Scope]
    protected function authoredBy(Builder $query, User $author): void
    {
        $query->whereBelongsTo($author, 'author');
    }

    private static function statusId(PostStatus $status): int
    {
        return DB::table('post_status')->where('label', $status->value)->value('id');
    }
}
```

### Domain rule or business rule?

| | Domain rule — **model** | Business rule — **Action** |
|---|---|---|
| About | this entity alone | a use case |
| Decided with | the entity's own attributes and relations | other aggregates, config, actor, time, quotas |
| True | always, in every flow, at every entry point | in this flow, under these conditions |
| Examples | a published post cannot be published again; an invoice total is the sum of its lines; a draft has no `published_at`; an archived post cannot go back to draft | only three active plans per tenant; publishing notifies followers and bumps a counter; a refund is allowed within 7 days on the current plan; this actor may publish at most 10 posts a day |

Two questions settle it:

1. **Would the rule still hold if this entity lived in a completely different
   application?** Yes → domain rule, model. No → business rule, Action.
2. **Does enforcing it need a query, a config value, the clock as policy, or another
   aggregate?** Then it is a business rule, and it does not belong on the model.

The model is the guardian of its own consistency: it refuses to enter an invalid
state, whoever asks. The Action is the source of business rules and the
orchestrator: it decides whether this use case may happen, in what order the effects
run, and what else must change.

Rules:

- **State transitions are methods**, and each one guards its own **invariants**
  before changing anything. `$post->publish($at)`, never `$post->status = 'published'`
  from the outside.
- **Invariants only — never use-case policy.** A transition method never reads
  config, never queries another aggregate, never asks who the actor is, never checks
  a quota. If a guard needs any of that, the guard belongs in the Action.
- **The method persists.** A self-contained transition may `save()`/`update()`
  itself; the surrounding Action provides the transaction so multiple transitions
  still commit as one unit.
- **Casts and relations are the model's job.** Every column with meaning gets a
  cast — enum, VO cast, `immutable_datetime`, `decimal:2`.
- **The model owns the enum ⇄ lookup mapping**, and it is the only place that reads
  the lookup table. Callers see the enum and never the `*_id` column.
- **Scopes carry every reusable predicate**, and they are always declared in
  **attribute form** — `#[Scope]` on a `protected` method typed `void` with a
  `Builder` first parameter. Never the `scopeXxx()` prefix.
- **Scopes are the query vocabulary.** If an Action writes a bare `where()`, the
  scope that should exist is missing. If a scope needs `whereRaw`, the builder
  method that replaces it exists — find it.
- **No static finders.** `Post::findPublishedBySlug()` is a scope plus a call site,
  or an Action. Keep query building out of static methods.
- **No cross-aggregate orchestration.** If a method needs to touch another
  aggregate or dispatch an event chain, that belongs in an Action.
- **No events, no notifications, no jobs from the model** — and no model events
  (`booted()`, observers) carrying business rules. Effects are ordered by the Action,
  where they are visible.
- **No container, no `config()`, no `auth()`** inside a model. Anything the entity
  cannot decide from itself is not its rule.
- **`final`**, and no `$fillable` wildcards — declare `$fillable` or `$guarded = []`
  deliberately and let Form objects be the input gate.

---

## Value objects and casts

Plain PHP, no package. A VO validates in its named constructor and is immutable.

```php
final readonly class Money
{
    private function __construct(
        public int $cents,
        public Currency $currency,
    ) {}

    public static function fromCents(int $cents, Currency $currency): self
    {
        throw_if($cents < 0, new NegativeMoney($cents));

        return new self($cents, $currency);
    }

    public function plus(self $other): self
    {
        throw_unless(
            $this->currency === $other->currency,
            new CurrencyMismatch($this->currency, $other->currency),
        );

        return new self($this->cents + $other->cents, $this->currency);
    }

    public function isZero(): bool
    {
        return $this->cents === 0;
    }
}
```

Rules:

- **`final readonly`, private constructor, named constructors** (`fromCents`,
  `fromString`, `now`). The constructor is the only place validity is decided.
- **Operations return new instances.** No setters, no mutation.
- **Equality is explicit** — add `equals(self $other): bool` when the VO is
  compared; do not rely on `==`.
- **A closed set is an enum, not a VO** — see the next section.

- **Casts are declared in the `casts()` method**, never the `$casts` property.
- **A VO reused across models, or one spanning several columns, gets a dedicated
  cast class** in `app/Casts/`, doing nothing but mapping:

  ```php
  final class MoneyCast implements CastsAttributes
  {
      public function get($model, string $key, $value, array $attributes): ?Money
      {
          return $value === null
              ? null
              : Money::fromCents((int) $value, Currency::from($attributes['currency']));
      }

      public function set($model, string $key, $value, array $attributes): array
      {
          if (! $value instanceof Money) {
              throw new InvalidArgumentException('Expected '.Money::class);
          }

          return ['total_cents' => $value->cents, 'currency' => $value->currency->value];
      }
  }
  ```

- **A single-column VO used by one model may use the inline cast** — an anonymous
  class right in `casts()`. Prefer it when a dedicated file would hold four lines of
  mapping and nothing else:

  ```php
  protected function casts(): array
  {
      return [
          'slug' => new class implements CastsAttributes
          {
              public function get($model, string $key, $value, array $attributes): ?Slug
              {
                  return $value === null ? null : Slug::fromString($value);
              }

              public function set($model, string $key, $value, array $attributes): ?string
              {
                  return $value?->value;
              }
          },
      ];
  }
  ```

  The moment a second model needs it, or the mapping touches more than one column,
  it moves to `app/Casts/` — inline is a convenience, not a hiding place.
- **The VO may carry its own cast** via `Castable::castUsing()` when the mapping is
  intrinsic to the VO and every model would declare the identical cast. Still one
  mapping, still no rules.

- **A VO never touches the container, the DB, or config.** It is pure.

---

## Action boundaries: DTOs and VOs

Nothing crosses an Action boundary loose. Every argument and every return value is
one of three things:

| Shape | When | Example |
|---|---|---|
| **Model** | the Action acts on an existing aggregate | `handle(Post $post, ...)` |
| **Value object** | the value has rules of its own | `PublishedAt`, `Money`, `Cpf` |
| **DTO** | several values travel together as one input or one result | `RegisterCustomerData`, `PublishResult` |

Never a primitive that means something (`string $cpf`, `int $cents`), never an
associative array, never `bool` as a result, never `mixed`.

### VO or DTO?

- A **value object** has invariants and behavior; it refuses to exist when invalid,
  and it answers questions (`$money->plus()`, `$cpf->masked()`).
- A **DTO** has no rules. It is a typed envelope: named fields, correct types,
  immutable, no behavior beyond named constructors. Its fields are themselves VOs,
  enums and models — a DTO of raw strings is just an array with a class name.

```php
namespace App\Data;

final readonly class RegisterCustomerData
{
    public function __construct(
        public string $name,
        public Email $email,
        public Cpf $document,
        public Money $creditLimit,
    ) {}

    public static function fromForm(CustomerForm $form): self
    {
        return new self(
            name: $form->name,
            email: Email::fromString($form->email),
            document: Cpf::fromString($form->document),
            creditLimit: Money::fromCents((int) $form->credit_limit_cents, Currency::BRL),
        );
    }
}
```

- **The conversion happens at the edge.** The entry point turns validated form
  input into VOs and a DTO; the Action never parses a string again.
- **A named constructor per source** — `fromForm()`, `fromRequest()`, `fromRow()`.
  The DTO is where the shape of the outside world stops.
- **Results get a DTO when the Action answers more than one thing.**

  ```php
  final readonly class PublishResult
  {
      public function __construct(
          public Post $post,
          public PublishedAt $publishedAt,
          public int $notifiedFollowers,
      ) {}
  }
  ```

- **DTOs live in `app/Data/` and end in `Data`** (or in a `Result` for outputs).
  They are `final readonly`, with promoted public properties.
- **No behavior creep.** The moment a DTO grows a rule, that rule belongs to a VO,
  the model, or the Action — not to the envelope.

---

## Enums and lookup tables

**Always string-backed.** Never `int`, never a pure (unbacked) enum for anything
persisted. Case names are `PascalCase`; backing values are `snake_case` and stable
forever — the value is a contract with the database.

```php
enum PostStatus: string
{
    case Draft = 'draft';
    case Published = 'published';
    case Archived = 'archived';

    public function canTransitionTo(self $next): bool
    {
        return match ($this) {
            self::Draft     => $next === self::Published,
            self::Published => $next === self::Archived,
            self::Archived  => false,
        };
    }

    public function label(): string
    {
        return __("post.status.{$this->value}");
    }

    public function isVisible(): bool
    {
        return $this === self::Published;
    }
}
```

**Every rule about the value lives on the enum**: transitions, labels, colors,
visibility, ordering, which cases a role may pick. The enum never queries, never
reads its own lookup table, never touches the container.

### The lookup table

A value the business names — a status, a type, a category, a kind — gets a lookup
table and a foreign key. A closed technical set nobody joins on (`Currency`,
`Locale`) stays a plain string column with the native enum cast.

The table is `id` + `label`, singular, named after the concept:

```php
Schema::create('post_status', function (Blueprint $table) {
    $table->id();
    $table->string('label')->unique();
});

Schema::create('posts', function (Blueprint $table) {
    $table->id();
    $table->foreignId('post_status_id')->constrained('post_status');
    // ...
});
```

- `label` holds the enum's **backing value verbatim** (`draft`, `published`). It is
  the join key, not display text — display text comes from `$status->label()` and
  is translated, never stored.
- Seed it from the enum in the same migration, so table and enum cannot drift:

  ```php
  DB::table('post_status')->insert(
      collect(PostStatus::cases())
          ->map(fn (PostStatus $case) => ['label' => $case->value])
          ->all(),
  );
  ```

- A new case is one enum case plus one migration inserting its row. Never insert by
  hand in production, never delete a row a foreign key still points at.
- **No Eloquent model for the lookup table.** It has no behavior and no invariants;
  a model would invite rules into it.
- No `created_at`/`updated_at`, no soft deletes, no extra columns. Anything beyond
  `id` + `label` means it is not a lookup table — it is a real entity.

### Mapping it on the model

The model that uses the enum implements one `Attribute` that converts both ways
with the `DB` facade, resolving by name:

```php
protected function status(): Attribute
{
    return Attribute::make(
        get: fn (mixed $value, array $attributes): PostStatus => PostStatus::from(
            DB::table('post_status')
                ->where('id', $attributes['post_status_id'])
                ->value('label'),
        ),
        set: fn (PostStatus $status): array => [
            'post_status_id' => self::statusId($status),
        ],
    );
}

private static function statusId(PostStatus $status): int
{
    return DB::table('post_status')->where('label', $status->value)->value('id');
}
```

Rules:

- **The attribute is named after the concept** (`status`), the column stays
  `post_status_id`. Nothing outside the model mentions the `*_id` column, and no
  caller ever handles a raw id.
- **The mutator takes the enum, never a string or an id.** Type-hint it so a wrong
  type fails loudly.
- **`DB` facade, not a relation.** A `belongsTo` would drag a lookup model in.
- **Scopes resolve through the same private helper**, so `where('status', ...)`
  never appears — the column does not hold the value.
- **Reading in a loop is the one thing to watch.** When a list renders hundreds of
  rows, memoize the id ⇄ label map in a `static array` on the model for the request;
  keep the shape above as the default.
- The lookup table is queried only by that attribute and its helper. If a query
  elsewhere touches `post_status`, the rule it is implementing belongs on the enum.

---

## Entry points

An **entry point** is where something outside the application asks for work: an
HTTP request, a terminal invocation, a browser interaction. There are exactly
three — **Controller**, **Console command**, **Livewire component** — and
all three follow the same contract, in the same order:

1. **Authorize** — policy or gate, for the actor performing the intent.
2. **Validate shape** — FormRequest, Form object, or an explicit validator for
   console options. Format only.
3. **Call one Action**, then present its result — redirect, response, console output.

Nothing else lives at an entry point: no query building, no transactions, no
persistence, no business rules, no event chains.

### Controller

Single-action controllers, one per intent, named after the same intent as the
Action. Authorization goes in the FormRequest, so it runs before the rules and the
controller body stays the delegation.

```php
final class PublishPostController
{
    public function __invoke(
        PublishPostRequest $request,
        Post $post,
        PublishPost $publish,
    ): RedirectResponse {
        $publish->handle($post, PublishedAt::now());

        return to_route('posts.show', $post);
    }
}
```

```php
final class PublishPostRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('publish', $this->route('post'));
    }

    public function rules(): array
    {
        return [
            'scheduled_for' => ['nullable', 'date', 'after:now'],
        ];
    }
}
```

- **A FormRequest on every write endpoint**, even one with no rules — it is where
  authorization lives.
- Route model binding converts ids to models; the controller never calls `find()`.
- The response is the controller's only other job: `to_route()`, a resource, a
  status code. No view logic, no data shaping beyond what the Action returned.

### Console command

Commands run **as the system**: there is no actor, so there is no policy call —
unless the command takes one (`--as=`), in which case it authorizes explicitly
with `Gate::forUser()`. Options are input like any other, so they are validated.

```php
final class PublishScheduledPostsCommand extends Command
{
    protected $signature = 'posts:publish-scheduled {--limit=100}';

    public function handle(DueScheduledPosts $due, PublishPost $publish): int
    {
        $data = Validator::make($this->options(), [
            'limit' => ['required', 'integer', 'min:1', 'max:1000'],
        ])->validate();

        $due->handle(Limit::of((int) $data['limit']))
            ->each(fn (Post $post) => $publish->handle($post, PublishedAt::now()));

        return self::SUCCESS;
    }
}
```

- **Actions by method injection** on `handle()`, same as everywhere else.
- The command does not query — a read Action supplies what it iterates.
- Exit codes are meaningful: `SUCCESS`, `FAILURE`, `INVALID`.
- Progress bars and `$this->info()` are presentation, and are the only extra thing
  a command is allowed to carry.

### Livewire component

The third entry point, and the one covered in detail in the next section:
`$this->authorize()` → `$this->form->validate()` → one Action call → redirect.

---

## Jobs and listeners

Jobs and listeners are **not entry points**. They run inside the application: the
input already arrived typed, and the edge that dispatched them already authorized.
They therefore carry only their own plumbing, plus one Action call.

**Own:** `$tries`, `$backoff`, `$timeout`, `retryUntil()`, `ShouldBeUnique`,
`middleware()` (`WithoutOverlapping`, `RateLimited`), queue and connection choice,
`failed()`, and — for listeners — whether the reaction is queued.

**Never:** validation, authorization, business rules, transactions, queries.

```php
final class PublishScheduledPost implements ShouldQueue
{
    public int $tries = 5;

    public int $timeout = 30;

    public function __construct(
        public readonly Post $post,
    ) {}

    public function backoff(): array
    {
        return [10, 60, 300];
    }

    public function middleware(): array
    {
        return [new WithoutOverlapping($this->post->id)];
    }

    public function handle(PublishPost $publish): void
    {
        $publish->handle($this->post, PublishedAt::now());
    }

    public function failed(Throwable $e): void
    {
        report($e);
    }
}
```

```php
final class SendPostPublishedNotification implements ShouldQueue
{
    public int $tries = 3;

    public function __construct(
        private readonly NotifyFollowers $notify,
    ) {}

    public function handle(PostPublished $event): void
    {
        $this->notify->handle($event->post);
    }
}
```

- **Jobs resolve Actions by method injection** on `handle()`; **listeners by
  constructor injection**, since Laravel passes only the event to `handle()`.
- **Constructors carry models, ids and VOs** — serializable payload, nothing else.
  `SerializesModels` for models.
- **`handle()` is one Action call.** Two calls means the missing concept is an
  Action that composes them.
- **Retry policy is a job concern, not a business rule.** "Retry three times with
  backoff" belongs on the job; "a payment may be attempted three times" belongs in
  the Action and the model.
- A job that needs to authorize is a job that was dispatched from the wrong place.
- Idempotency is designed into the Action (guarded transitions throw), so a retry
  that runs twice is safe by construction, not by a flag on the job.

---

## External services: gateways

No Action, model, component, job or controller ever calls `Http::` directly. Every
call out of the application goes through two classes with one responsibility each.

| Class | Speaks | Owns | Never |
|---|---|---|---|
| **Client** | the vendor's wire format | base URL, auth, headers, timeouts, transport retries, raw request/response | domain vocabulary, business rules |
| **Gateway** | the domain | translating VOs/DTOs → request payload and response → VOs/DTOs, mapping vendor failures to domain exceptions | HTTP mechanics |

```php
namespace App\Gateways\Pagarme;

final class PagarmeClient
{
    public function __construct(
        private readonly string $baseUrl,
        private readonly string $apiKey,
    ) {}

    public function post(string $path, array $payload): array
    {
        return Http::baseUrl($this->baseUrl)
            ->withToken($this->apiKey)
            ->timeout(10)
            ->retry(3, 200)
            ->acceptJson()
            ->post($path, $payload)
            ->throw()
            ->json();
    }
}
```

```php
final class PagarmeGateway implements PaymentGateway
{
    public function __construct(
        private readonly PagarmeClient $client,
    ) {}

    public function charge(ChargeData $charge): ChargeResult
    {
        try {
            $response = $this->client->post('/charges', [
                'amount'   => $charge->amount->cents,
                'currency' => $charge->amount->currency->value,
                'document' => $charge->document->digits(),
            ]);
        } catch (RequestException $e) {
            throw ChargeRejected::fromVendor('pagarme', $e);
        }

        return new ChargeResult(
            id: ChargeId::fromString($response['id']),
            status: ChargeStatus::from($response['status']),
            paid: Money::fromCents($response['amount'], Currency::BRL),
        );
    }
}
```

Rules:

- **The Gateway's signature is domain-shaped**: DTOs and VOs in, DTOs and VOs out.
  A vendor field name never leaves the Gateway; a domain type never enters the Client.
- **The Client is dumb on purpose.** It knows how to talk, not what is being said.
  Arrays in, arrays out — that is the one place raw shapes are allowed.
- **Vendor failures become domain exceptions** in the Gateway, and those exceptions
  render themselves like any other. An Action never catches a `RequestException`.
- **Transport retry belongs to the Client** (`->retry()`), business retry to the job.
  Two different concerns that happen to share a word.
- **Credentials and URLs come from `config/services.php`**, injected into the Client
  constructor by a service provider. No `env()` outside config, no inline secrets.
- **Actions type-hint the Gateway** (or its contract) and call one method. The
  Gateway is a collaborator like any other.

### More than one implementation: contract + adapters

The moment a second vendor appears — or a sandbox implementation that is more than
a test double — the Gateway becomes a **contract** and each vendor an **adapter**.

```php
namespace App\Contracts;

interface PaymentGateway
{
    public function charge(ChargeData $charge): ChargeResult;

    public function refund(ChargeId $id, Money $amount): RefundResult;
}
```

```php
// app/Providers/PaymentServiceProvider.php
$this->app->bind(PaymentGateway::class, fn () => match (config('services.payment.driver')) {
    'pagarme' => $this->app->make(PagarmeGateway::class),
    'stripe'  => $this->app->make(StripeGateway::class),
});
```

- **The interface is written in domain terms**, never as the union of what the
  vendors happen to offer. If an adapter cannot satisfy it, that is a real gap —
  throw an `UnsupportedOperation` domain exception, do not widen the interface.
- **One adapter per vendor**, each with its own Client. Adapters never call each
  other and never share a base class carrying vendor logic.
- **Bind by config**, resolved in a service provider. Nothing else selects the
  implementation; Actions depend on the interface only.
- **One contract test, run against every adapter**, asserting the same domain
  behavior. Vendor specifics are tested per adapter with `Http::fake()`.
- Do not introduce a contract for a single vendor. One implementation is a Gateway
  class; the interface arrives with the second one.

---

## Livewire components

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
  method means the missing concept is a third Action.
- **`#[Computed]` for anything the view derives.** No queries in the template, no
  `@php` blocks.
- **A Form object for every write form** (`public PostForm $form;`). No loose public
  props for user input, and no inline `$this->validate([...])` rule arrays — the
  rules live on the Form object.
- **Read queries for the view go through model scopes or a read Action**, called
  from a `#[Computed]` method. Never a query builder chain in the component.
- **The component never opens a transaction** and never calls `save()`.
- **`wire:model` binds to `form.*`.** Bind to a plain public prop only for UI state
  (open tabs, filters, search terms).
- **Full-page components own the route**; nested components receive their data as
  parameters and stay presentational.
- **Templates carry no logic** beyond `@if`/`@foreach` over prepared data, and every
  user-facing string goes through `__()`.
- **`wire:submit` on the form element**, not a click handler on the button — the
  form is the intent.

## Validation boundary

Every entry point validates the shape of its own input, with the tool that fits
it: a **FormRequest** in a controller, a **Form object** in a Livewire component,
an explicit **Validator** over the options in a console command. All three decide
one thing — is the input *well-formed* — and nothing else.

```php
namespace App\Livewire\Forms;

final class PostForm extends Form
{
    #[Validate('required|string|max:120')]
    public string $title = '';

    #[Validate('required|string|min:10')]
    public string $body = '';

    #[Validate('nullable|date|after:now')]
    public ?string $scheduled_for = null;
}
```

| Kind of rule | Where |
|---|---|
| required, max, min, date, email, unique, mimes | Form object / FormRequest / console validator |
| "amount cannot be negative", "currencies must match" | VO named constructor |
| "a published post cannot be published again" — domain rule | Model transition method |
| "only three active plans per tenant", anything cross-aggregate — business rule | Action |

The Action never re-checks shape, and the Form object never encodes a business
rule. If a rule needs a DB lookup beyond `unique`, it is a business rule.

Jobs and listeners validate nothing: their input came from an entry point that
already did.

---

## Authorization

Standard Laravel policies, enforced **at the entry point** — the component, the
FormRequest, or (when a command acts for a user) `Gate::forUser()`. The Action
assumes its caller has authorized.

```php
$publish = function (PublishPost $publish) {
    $this->authorize('publish', $this->post);
    // ...
};
```

- One policy per model, methods named after the intent (`publish`, `refund`), not
  only the CRUD verbs.
- Full-page components also carry route middleware (`auth`, `can:`), so an
  unauthenticated hit never reaches the component.
- The Blade half hides what the policy denies (`@can`), but hiding is never the
  enforcement — the `authorize()` call is.
- **Controllers authorize in the FormRequest's `authorize()`**, so it runs before
  the rules and before the controller body.
- **Console commands run as the system** and skip policies, unless they take an
  actor (`--as=`) — then they authorize explicitly with `Gate::forUser()`.
- **Jobs and listeners never authorize.** The entry point that dispatched them did.
  A job that needs a policy check was dispatched from the wrong place.

---

## Errors

Domain failures are typed exceptions that know how they are presented. Components
carry no `try`/`catch`.

```php
namespace App\Exceptions;

final class AlreadyPublished extends DomainException
{
    public function __construct(public readonly int $postId)
    {
        parent::__construct("Post {$postId} is already published.");
    }

    public function render(): void
    {
        $this->notify(
            level: 'danger',
            message: __('This post has already been published.'),
        );
    }
}
```

- Base `DomainException` holds the shared `notify()` binding — a Flux toast when
  the project uses Flux, otherwise a dispatched browser event or a flashed
  session message. One binding, one place to change it.
- **One exception class per rule**, named after the rule, carrying the ids that
  explain it. No generic `BusinessException` with a string.
- Exceptions are for **broken invariants**, not for expected branches. "No results"
  is an empty collection; "not found" is route model binding's 404.
- Anything without a `render()` bubbles to the Laravel handler and is a bug.

---

## Testing

Pest, feature-first. Feature tests drive the Livewire component; unit tests cover VOs
and pure domain methods.

```php
it('publishes a draft post', function () {
    $post = Post::factory()->draft()->create();

    Livewire::test('posts.edit', ['post' => $post])
        ->call('publish')
        ->assertHasNoErrors();

    expect($post->refresh()->status)->toBe(PostStatus::Published);
});

it('refuses to publish twice', function () {
    $post = Post::factory()->published()->create();

    expect(fn () => app(PublishPost::class)->handle($post, PublishedAt::now()))
        ->toThrow(AlreadyPublished::class);
});

it('rejects negative money', function () {
    expect(fn () => Money::fromCents(-1, Currency::BRL))
        ->toThrow(NegativeMoney::class);
});
```

Rules:

- **Assert the layer that implements the rule**: returned values, persisted state
  (`assertDatabaseHas`), dispatched events (`Event::assertDispatched`), thrown
  domain exceptions, redirects, error bags.
- **Never assert rendered output** — no `assertSee`, no `assertSeeText`, no markup
  or Blade assertions, no browser/E2E (Dusk, Cypress, Playwright), no component
  snapshots. A test that breaks when screen text changes is at the wrong layer.
- **Fake the Gateway, not the HTTP layer.** Feature tests bind a fake
  implementation of the contract (or a stub Gateway) in the container. `Http::fake()`
  appears only in the Client's and the adapter's own tests.
- **A factory per model**, with named states (`draft()`, `published()`,
  `overdue()`). No seeders in tests, no shared fixture data.
- **One test per rule or edge case.** Do not re-cover an Action's rule from three
  components.
- Every Action gets at least: the happy path, and one test per invariant it
  enforces.

---

## Anti-patterns

| Do not | Do |
|---|---|
| `PostService`, `PostManager`, `PostRepository` | one Action per intent |
| business logic in a component method | Action called from the method |
| a separate class file + view for a component | one single-file component |
| `$this->validate(['title' => 'required'])` inline | rules on the Form object |
| a controller that queries, transforms, or persists | FormRequest → Action → response |
| business logic in a job's `handle()` | retry config on the job, logic in the Action |
| `$this->authorize()` or validation inside a job | authorize and validate at the entry point |
| a fat listener reacting with rules of its own | listener config + one Action call |
| a console command building queries in a loop | read Action, then write Action |
| `DB::transaction()` in a component | transaction inside `handle()` |
| primitives crossing layers (`string $currency`) | VO or string-backed enum |
| `handle(array $data)` / `handle(int $id, string $name, ...)` | one DTO, or models + VOs |
| an Action returning `bool` or an associative array | model, VO, or result DTO |
| a DTO of raw strings | DTO whose fields are VOs, enums and models |
| a DTO that grew a rule | rule on the VO, the model, or the Action |
| `Http::` inside an Action, model, job or component | Gateway + Client |
| vendor field names leaking past the Gateway | domain DTOs in and out |
| catching `RequestException` in an Action | Gateway maps it to a domain exception |
| an interface for a single vendor | Gateway class now, contract with the 2nd vendor |
| an interface shaped by the vendors' feature union | domain-shaped contract, `UnsupportedOperation` for gaps |
| int-backed enums, unbacked enums for stored values | string-backed, snake_case values |
| an Eloquent model for `post_status` | `id` + `label` table, `DB` facade in one attribute |
| a rule reading the lookup table (`->where('label', ...)` for logic) | the rule on the enum |
| storing display text in `label` | `label` = backing value; text from `$status->label()` |
| passing `post_status_id` around | pass the enum; only the model knows the column |
| query builder chains inside a component | scope, or read Action |
| `scopePublished()` prefix methods | `#[Scope] protected function published()` |
| `->whereRaw('status_id = 3')`, interpolated SQL | scope + builder methods, bindings only |
| `->where('post_status_id', 3)` in an Action | a `#[Scope]` that names the predicate |
| a repository or query-object layer | `Model::query()` composed in the Action |
| an Action returning a `Builder` | return models, collections or VOs |
| one report class with `$groupBy` flags | one Action per report, named after the answer |
| `$post->status = 'published'` from outside | `$post->publish($at)` |
| a quota, config or actor check inside a model method | the check in the Action |
| `config()`, `auth()` or a query inside a model | pass it in, or decide it in the Action |
| observers / `booted()` hooks carrying business rules | effects ordered explicitly in the Action |
| an Action re-checking an invariant the model owns | let the model throw |
| business rules in `#[Validate]` | Form = shape, Action = rules |
| `try`/`catch` around Actions in components | self-rendering domain exception |
| `assertSee('Published')` | `expect($post->refresh()->status)->toBe(...)` |
| static finders on models | scope + call site, or an Action |

---

## Review checklist

- [ ] Every write goes through an Action with `handle()` and a transaction.
- [ ] Action names are verb + noun; no `*Service` / `*Manager` classes.
- [ ] Actions receive VOs, DTOs or models — never loose primitives, arrays or `request()`.
- [ ] Action returns are models, VOs or result DTOs — never `bool` or an array.
- [ ] DTOs are `final readonly`, in `app/Data/`, with VO/enum fields and named constructors.
- [ ] No `Http::` outside a Client; every external call goes Gateway → Client.
- [ ] Vendor errors become domain exceptions inside the Gateway.
- [ ] Two or more vendors: a domain-shaped contract, one adapter each, bound by config.
- [ ] Model transitions guard their invariants before changing state.
- [ ] Models carry domain rules only — no config, no queries, no actor, no events.
- [ ] Every business rule lives in an Action, not on the model or in a component.
- [ ] No query building outside scopes, read Actions, and `computed()`.
- [ ] All scopes use `#[Scope]`; no `scopeXxx()` prefixes anywhere.
- [ ] No raw `where` — raw appears only for aggregates inside a report Action.
- [ ] Reports are their own Action, named after the answer, returning VOs.
- [ ] Every meaningful column has an enum, VO cast, or native cast.
- [ ] Enums are string-backed and hold every rule about the value.
- [ ] Lookup tables are `id` + `label` only, seeded from the enum, no model.
- [ ] The enum ⇄ lookup mapping is one `Attribute` on the model; no `*_id` leaks out.
- [ ] VOs are `final readonly` with private constructors and named factories.
- [ ] Every entry point: authorize → validate → one Action → present.
- [ ] Components are single-file `new class extends Component`, methods thin.
- [ ] Controllers are single-action, with a FormRequest carrying `authorize()`.
- [ ] Console commands validate their options and never query directly.
- [ ] Jobs and listeners hold only retry/queue config plus one Action call.
- [ ] Form objects hold only shape rules.
- [ ] Domain exceptions are typed, per-rule, and render themselves.
- [ ] Tests assert state, events and exceptions — never rendered output.
