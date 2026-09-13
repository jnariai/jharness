# Laravel coding guidelines

<!-- harness-meta:start -->
Drop this into a Laravel project as `docs/agents/coding_guidelines.md`. It is the
convention layer agents must follow when writing code in that project: `/plan`
decomposes against it, `ralph.sh` sessions read it before the first edit.
`/ai-context` copies it there automatically when the target is a Laravel repo and
the file is absent — with `guidelines/livewire.md` appended when the project also
requires Livewire. `/jharness:update` refreshes a copy that was never edited.
This block is stripped from the copy.

> Keep it hand-written there — without the `/ai-context` banner on line 3 the
> generator never clobbers it. Do not run `/ai-context --adopt` on this file.
<!-- harness-meta:end -->

Stack assumed: Laravel 12+, Pest, PHP 8.2+ (readonly classes, backed enums).
Projects using Livewire also follow the Livewire guidelines, which build on these.

---

## Golden rules

1. **Actions own writes, and orchestrate them.** Every state change goes through an
   Action class with a `handle()` method that opens the transaction and decides,
   top to bottom, everything that happens in its use case: model transitions,
   gateway calls, and the events that announce the result. Nothing else writes.
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
8. **What happened is an event; what follows is a listener.** An Action announces a
   domain fact (`PaymentPaid`) once it is committed. Each consequence in another
   aggregate — mark the order paid, issue the invoice — is a listener calling its
   own Action. The emitting Action never knows who listens.
9. **Every external call goes through a Gateway.** A Client transports, a Gateway
   translates — outbound calls and inbound webhooks alike; more than one vendor
   means a contract plus adapters.
10. **Explicit construction over container bindings.** Autowire concrete classes.
    Anything whose construction needs config or runtime data — a gateway configured
    per tenant — is built by a Factory with `new`. Bindings hide what runs; keep
    them rare.
11. **FormRequests are shape only.** Required, max, unique, format. Never a business
    rule.
12. **Domain exceptions render themselves.** No error plumbing at entry points.
13. **Reads are Eloquent + scopes, composed in an Action.** `#[Scope]` attributes are
    the vocabulary, raw `where` is banned, and a report gets an Action of its own.
14. **Everything typed; only DTOs and VOs are `final readonly`.** No `mixed`, no
    untyped properties, no array-shaped payloads where a VO or enum fits. Every
    other class stays open — no `final` on Actions, models, gateways, factories,
    controllers or jobs.
15. **Test everything, backend features first.** Feature tests of backend behavior
    come before anything else; unit, gateway and frontend tests follow.
16. **Code explains itself; comments are for shenanigans.** Names and types carry
    the meaning. A comment appears only when the code cannot say it — a workaround,
    a vendor quirk, a hidden ordering, a deliberate oddity someone would "fix".

---

## Layer map

| Layer | Path | Owns | Never |
|---|---|---|---|
| Controller | `app/Http/Controllers/*.php` | authorize + validate (via FormRequest), call Action, respond | business rules, queries, transactions |
| Console command | `app/Console/Commands/*.php` | validate options, call Action, report | business rules, queries, transactions |
| FormRequest | `app/Http/Requests/*Request.php` | shape validation of input, authorization | business rules, persistence |
| Job | `app/Jobs/*.php` | retries, backoff, timeout, uniqueness, overlap, `failed()` — then one Action call | validation, authorization, business rules |
| Event | `app/Events/*.php` | a past-tense domain fact + its payload (model, ids, VOs) | behavior, rules, knowing its listeners |
| Listener | `app/Listeners/*.php` | one reaction to one event: queue config — then one Action call | validation, authorization, business rules, deciding whether to react |
| Action | `app/Actions/<Aggregate>/*.php` | every write, business rules, orchestration, transaction boundary, composing reads from scopes, reports | HTTP/UI concerns, validation of shape, raw `where`, re-checking model invariants |
| Model | `app/Models/*.php` | domain rules: its own invariants, state transitions, relations, casts, `#[Scope]` predicates, enum ⇄ lookup id mapping | business rules, cross-aggregate orchestration, events, config, static finders |
| Value object | `app/ValueObjects/*.php` | its own validity + behavior | persistence, container access |
| DTO | `app/Data/*Data.php` | typed transport across an Action boundary | rules, behavior, persistence |
| Gateway | `app/Gateways/<Vendor>/*Gateway.php` | domain ⇄ vendor translation, vendor errors → domain exceptions | HTTP mechanics, retries, headers, reading config |
| Client | `app/Gateways/<Vendor>/*Client.php` | transport: base URL, auth, headers, timeout, transport retries | domain knowledge, business rules, reading config |
| Factory | `app/Gateways/<Vendor>/*GatewayFactory.php` | building Client + Gateway with `new` from config and runtime data (tenant) | calling the vendor, business rules |
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

class PublishPost
{
    public function __construct(
        private readonly Dispatcher $events,
    ) {}

    public function handle(Post $post, PublishedAt $at): Post
    {
        return DB::transaction(function () use ($post, $at) {
            $post->publish($at);
            $post->author->increment('published_count');
            $this->events->dispatch(new PostPublished($post));

            return $post;
        });
    }
}
```

### Actions own writes, and orchestrate them

The Action is the only place a write starts, and the only place that decides the
order of its effects. Reading `handle()` top to bottom tells the whole story of the
use case: which transitions run, which other aggregates change, which gateway is
called, which events and jobs go out — and in what order.

- **Nothing writes behind its back.** Controllers, console commands, components,
  jobs and listeners never call `save()`, `update()`, `create()` or `delete()`.
  Observers and model events never write either.
- **The model executes, the Action orchestrates.** `$post->publish($at)` changes
  and persists one entity; deciding that publishing also bumps a counter and
  notifies followers is the Action's job.
- **An Action may compose other Actions** when a use case is made of smaller ones:
  inject them and call their `handle()`. The outermost Action owns the
  transaction; the inner ones join it.
- **Effects are explicit calls, in order.** Events are dispatched and jobs queued by
  the Action after the state they describe exists — never from a model hook.
- **Its own use case directly, other aggregates through events.** What must succeed
  or fail together with the write is a direct call inside the transaction; what
  merely reacts to it — in another aggregate, or able to run later — is a listener
  on the event the Action dispatches. See *Events: facts and reactions*.

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
  that will drift. The one exception is **at-least-once input** — a redelivered
  webhook, a retried queued listener: there "already applied" is an expected
  branch, so the Action checks the state and returns early instead of throwing.
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
class SendOverdueReminders
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
class MonthlyRevenueByRegion
{
    public function handle(Period $period): Collection
    {
        return Invoice::query()
            ->issuedWithin($period)
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

class Post extends Model
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
            'status'       => PostStatus::Published,
            'published_at' => $at,
        ]);
    }

    public function isPublished(): bool
    {
        return $this->status === PostStatus::Published;
    }

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
  (`booted()`, observers) carrying business rules or writes. Effects are ordered by
  the Action, where they are visible.
- **No container, no `config()`, no `auth()`** inside a model. Anything the entity
  cannot decide from itself is not its rule.
- **No `$fillable` wildcards** — declare `$fillable` or `$guarded = []`
  deliberately and let FormRequests be the input gate.

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
  class MoneyCast implements CastsAttributes
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

    public static function fromRequest(RegisterCustomerRequest $request): self
    {
        return new self(
            name: $request->string('name')->value(),
            email: Email::fromString($request->string('email')->value()),
            document: Cpf::fromString($request->string('document')->value()),
            creditLimit: Money::fromCents($request->integer('credit_limit_cents'), Currency::BRL),
        );
    }
}
```

- **The conversion happens at the edge.** The entry point turns validated input
  into VOs and a DTO; the Action never parses a string again.
- **A named constructor per source** — `fromRequest()`, `fromForm()`, `fromRow()`.
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
  They are `final readonly`, with promoted public properties — together with VOs,
  the only `final` classes in the codebase.
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
three — **Controller**, **Console command**, **Livewire component** (see the
Livewire guidelines) — and all three follow the same contract, in the same order:

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
class PublishPostController
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
class PublishPostRequest extends FormRequest
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
- **Webhooks are controllers too**: the FormRequest verifies the vendor's signature
  in `authorize()`, then one Action. See *Events: facts and reactions*.

### Console command

Commands run **as the system**: there is no actor, so there is no policy call —
unless the command takes one (`--as=`), in which case it authorizes explicitly
with `Gate::forUser()`. Options are input like any other, so they are validated.

```php
class PublishScheduledPostsCommand extends Command
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

---

## Jobs and listeners

Jobs and listeners are **not entry points**. They run inside the application: the
input already arrived typed, and the edge that dispatched them already authorized.
They therefore carry only their own plumbing, plus one Action call.

**Own:** `$tries`, `$backoff`, `$timeout`, `retryUntil()`, `ShouldBeUnique`,
`middleware()` (`WithoutOverlapping`, `RateLimited`), queue and connection choice,
`failed()`, and — for listeners — whether the reaction is queued.

**Never:** validation, authorization, business rules, transactions, queries, writes.

```php
class PublishScheduledPost implements ShouldQueue
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
class SendPostPublishedNotification implements ShouldQueue
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
- Idempotency is designed into the Action, not bolted onto the job: a transition
  never applies twice, and an Action fed by retries returns early when its state is
  already applied.

---

## External services: gateways

No Action, model, component, job or controller ever calls `Http::` directly. Every
call out of the application goes through a Gateway and its Client, and both are
built by a Factory.

| Class | Speaks | Owns | Never |
|---|---|---|---|
| **Client** | the vendor's wire format | base URL, auth, headers, timeouts, transport retries, raw request/response | domain vocabulary, business rules, reading config |
| **Gateway** | the domain | translating VOs/DTOs → request payload and response → VOs/DTOs, verifying and translating inbound webhooks into DTOs, mapping vendor failures to domain exceptions | HTTP mechanics, reading config |
| **Factory** | construction | reading config and runtime data (the tenant's credentials, a per-tenant URL), then `new` Client + Gateway | calling the vendor, business rules |

```php
namespace App\Gateways\Pagarme;

class PagarmeClient
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
class PagarmeGateway implements PaymentGateway
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

```php
class PagarmeGatewayFactory
{
    public function forTenant(Tenant $tenant): PagarmeGateway
    {
        return new PagarmeGateway(
            new PagarmeClient(
                baseUrl: config('services.pagarme.url'),
                apiKey: $tenant->paymentCredentials()->apiKey,
            ),
        );
    }
}
```

```php
class ChargeOrder
{
    public function __construct(
        private readonly PagarmeGatewayFactory $gateways,
    ) {}

    public function handle(Order $order): ChargeResult
    {
        return DB::transaction(function () use ($order) {
            $result = $this->gateways
                ->forTenant($order->tenant)
                ->charge(ChargeData::fromOrder($order));

            $order->markCharged($result->id);

            return $result;
        });
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
- **A gateway whose construction needs config or runtime data is built by its
  Factory** — which is nearly every gateway. The factory method is named after what
  varies: `forTenant(Tenant $tenant)`, `forRegion(Region $region)`, or `make()` when
  only static config is involved.
- **The Factory is the only place config meets the gateway.** It reads
  `config('services.*')` and the tenant's settings and passes plain values into the
  constructors. The Client and the Gateway never call `config()`, never look up the
  tenant, never resolve anything. No `env()` outside config files, no inline secrets.
- **Actions inject the Factory** (autowired — no registration) and call the gateway
  it returns. The Action shows which tenant's gateway is used, right at the call.
- **No container binding for a gateway.** No `bind()`/`singleton()` building the
  Client in a service provider, no contextual `when()->needs()->give()` for its
  credentials. A binding hides which implementation runs and with whose
  credentials; the factory call makes both visible.

### More than one implementation: contract + adapters

The moment a second vendor appears — or a sandbox implementation that is more than
a test double — the Gateway becomes a **contract** and each vendor an **adapter**.
The choice between adapters is one more thing a factory builds.

```php
namespace App\Contracts;

interface PaymentGateway
{
    public function charge(ChargeData $charge): ChargeResult;

    public function refund(ChargeId $id, Money $amount): RefundResult;
}
```

```php
class PaymentGatewayFactory
{
    public function __construct(
        private readonly PagarmeGatewayFactory $pagarme,
        private readonly StripeGatewayFactory $stripe,
    ) {}

    public function forTenant(Tenant $tenant): PaymentGateway
    {
        return match ($tenant->paymentProvider()) {
            PaymentProvider::Pagarme => $this->pagarme->forTenant($tenant),
            PaymentProvider::Stripe  => $this->stripe->forTenant($tenant),
        };
    }
}
```

- **The interface is written in domain terms**, never as the union of what the
  vendors happen to offer. If an adapter cannot satisfy it, that is a real gap —
  throw an `UnsupportedOperation` domain exception, do not widen the interface.
- **One adapter per vendor**, each with its own Client and its own factory.
  Adapters never call each other and never share a base class carrying vendor
  logic.
- **The factory selects the adapter**, from a string-backed enum on the tenant or
  from config — never a service-provider binding of the interface. Actions depend
  on the interface and receive it from the factory.
- **One contract test, run against every adapter**, asserting the same domain
  behavior. Vendor specifics are tested per adapter with `Http::fake()`.
- Do not introduce a contract for a single vendor. One implementation is a Gateway
  class; the interface arrives with the second one.

---

## Events: facts and reactions

A little event-driven design, on Laravel's own events. An Action changes its
aggregate and **announces the fact**; everything that follows in other aggregates
**reacts** to it, each reaction in its own listener and its own Action.

### The flow, from a payment webhook

```
POST /webhooks/pagarme/{tenant}
  → PagarmeWebhookRequest     authorize(): gateway verifies the signature
  → PagarmeWebhookController  one Action call
  → ReceivePaymentWebhook     gateway translates payload → domain DTO;
                              payment->markPaid(); dispatch PaymentPaid
      ⇢ MarkOrderAsPaid        → PayOrder       (Order aggregate)
      ⇢ IssueInvoiceForPayment → IssueInvoice   (Invoice aggregate)
      ⇢ SendPaymentReceipt     → SendReceipt    (notification)
```

**Entry point** — the webhook is a controller like any other. There is no user, so
"authorize" means verifying the vendor's signature, which the Gateway knows how to
do (`authorize()` on a FormRequest accepts injected dependencies):

```php
class PagarmeWebhookRequest extends FormRequest
{
    public function authorize(PagarmeGatewayFactory $gateways): bool
    {
        return $gateways
            ->forTenant($this->route('tenant'))
            ->verifiesWebhook($this->getContent(), (string) $this->header('X-Hub-Signature'));
    }

    public function rules(): array
    {
        return [
            'id'          => ['required', 'string'],
            'type'        => ['required', 'string'],
            'data.status' => ['required', 'string'],
        ];
    }
}
```

```php
class PagarmeWebhookController
{
    public function __invoke(
        PagarmeWebhookRequest $request,
        Tenant $tenant,
        ReceivePaymentWebhook $receive,
    ): Response {
        $receive->handle($tenant, WebhookPayload::fromRequest($request));

        return response()->noContent();
    }
}
```

**Action** — translates through the Gateway, applies the transition to its own
aggregate, and dispatches the fact. It knows nothing about orders or invoices:

```php
class ReceivePaymentWebhook
{
    public function __construct(
        private readonly PagarmeGatewayFactory $gateways,
    ) {}

    public function handle(Tenant $tenant, WebhookPayload $payload): Payment
    {
        $update = $this->gateways->forTenant($tenant)->translateWebhook($payload);

        return DB::transaction(function () use ($update) {
            $payment = Payment::query()->forCharge($update->chargeId)->lockForUpdate()->firstOrFail();

            if ($update->status !== PaymentStatus::Paid || $payment->isPaid()) {
                return $payment;                       // not ours to act on, or a redelivery
            }

            $payment->markPaid($update->occurredAt);
            PaymentPaid::dispatch($payment);           // delivered after commit

            return $payment;
        });
    }
}
```

**Event** — a past-tense fact with its payload, nothing more:

```php
namespace App\Events;

class PaymentPaid implements ShouldDispatchAfterCommit
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public readonly Payment $payment,
    ) {}
}
```

**Listeners** — one reaction each, queued, one Action call:

```php
class MarkOrderAsPaid implements ShouldQueue
{
    public int $tries = 5;

    public function __construct(
        private readonly PayOrder $payOrder,
    ) {}

    public function handle(PaymentPaid $event): void
    {
        $this->payOrder->handle($event->payment->order);
    }
}

class IssueInvoiceForPayment implements ShouldQueue
{
    public function __construct(
        private readonly IssueInvoice $issue,
    ) {}

    public function handle(PaymentPaid $event): void
    {
        $this->issue->handle($event->payment);
    }
}
```

Whether an invoice is due at all — the tenant has invoicing on, the amount is above
a threshold — is a business rule of `IssueInvoice`, not a condition on the listener.

### Direct call or event?

| Direct call inside the Action | Event + listener |
|---|---|
| must succeed or fail together with the write — same transaction | reacts to a fact that is already true |
| part of what this use case *is* | belongs to another aggregate or module (order, invoice, notification) |
| the caller needs its result | can run later, retry on its own, fail without undoing the fact |
| e.g. mark the payment paid, record the charge id | e.g. mark the order paid, issue the invoice, email the receipt |

### Rules

- **Events are domain facts in the past tense**: `PaymentPaid`, `OrderShipped`,
  `InvoiceIssued`. Never a command (`SendInvoice`) and never a technical change
  (`PaymentUpdated`, `PaymentSaved`).
- **Only Actions dispatch domain events**, after the state they describe exists.
  Never from a model, an observer, a controller or a component.
- **`ShouldDispatchAfterCommit` on every domain event**, so no listener — sync or
  queued — ever sees state that is later rolled back.
- **The payload is the aggregate model (with `SerializesModels`), or ids and VOs.**
  Properties are `public readonly`; the event carries no behavior and no rules.
- **One listener = one reaction = one Action call.** The listener holds queue
  config (`ShouldQueue`, `$tries`, `$backoff`) and nothing else — never an `if`
  deciding whether to react. That decision is a business rule of the Action it calls.
- **Listeners are queued by default.** A reaction that must be visible in the same
  response is not a reaction — it is a direct call in the Action.
- **The emitting Action never knows its listeners.** Adding a reaction is adding a
  listener; the Action and the event do not change.
- **At-least-once, everywhere.** Webhooks are redelivered and queued listeners
  retry, so every Action they reach returns early when its state is already applied,
  and the event is dispatched only on the real transition — never on a redelivery.
- **Chains go through Actions.** A listener's Action may dispatch its own fact
  (`PayOrder` → `OrderPaid`); a listener never dispatches an event itself. Keep
  chains shallow and never let them loop back to the aggregate that started them.
- **Events do not return data.** Nothing waits on a listener's result; if the
  caller needs it, it is a direct call.
- **Registration is event discovery**: the listener's `handle(PaymentPaid $event)`
  type hint is the subscription. `php artisan event:list` shows the full wiring.
- **Webhook payloads never reach an Action raw.** The Gateway verifies the
  signature and translates the vendor's payload into a domain DTO
  (`PaymentStatusUpdate`), exactly as it does for outbound responses.

---

## Construction: factories over container bindings

The container is used for **autowiring**, not for configuration. Reading a class's
constructor, and the line that creates it, should be enough to know exactly what
runs.

- **Autowire concrete classes.** Constructor and method injection of Actions,
  factories and other concrete classes needs no registration and hides nothing.
- **Build with a Factory when construction needs data.** Config values, a tenant's
  settings, a choice between implementations — a Factory takes them in and calls
  `new`. The caller injects the factory and passes the runtime data to it.
- **Avoid bindings.** `bind()`, `singleton()`, `scoped()`, contextual binding and
  interface → implementation bindings in service providers move construction away
  from its use; the reader of the Action cannot see what it receives.
- **When one is unavoidable** — a framework or package extension point that expects
  a binding — keep it in a single provider with a comment saying why.
- **No service location.** No `app()`, `resolve()` or `App::make()` in application
  code; inject instead.
- **Tests may use the container** to swap a factory:
  `$this->instance(PaymentGatewayFactory::class, $fake)`. That is test wiring, not
  application design — and it works because factories are not `final`.

---

## Validation boundary

Every entry point validates the shape of its own input, with the tool that fits
it: a **FormRequest** in a controller, an explicit **Validator** over the options
in a console command, a **Form object** in a Livewire component. All of them decide
one thing — is the input *well-formed* — and nothing else.

| Kind of rule | Where |
|---|---|
| required, max, min, date, email, unique, mimes | FormRequest / console validator / Livewire Form object |
| "amount cannot be negative", "currencies must match" | VO named constructor |
| "a published post cannot be published again" — domain rule | Model transition method |
| "only three active plans per tenant", anything cross-aggregate — business rule | Action |

The Action never re-checks shape, and a FormRequest never encodes a business
rule. If a rule needs a DB lookup beyond `unique`, it is a business rule.

Jobs and listeners validate nothing: their input came from an entry point that
already did.

---

## Authorization

Standard Laravel policies, enforced **at the entry point** — the FormRequest, the
Livewire component, or (when a command acts for a user) `Gate::forUser()`. The
Action assumes its caller has authorized.

- One policy per model, methods named after the intent (`publish`, `refund`), not
  only the CRUD verbs.
- Routes also carry middleware (`auth`, `can:`), so an unauthenticated hit never
  reaches the entry point.
- Blade hides what the policy denies (`@can`), but hiding is never the
  enforcement — the policy check at the entry point is.
- **Controllers authorize in the FormRequest's `authorize()`**, so it runs before
  the rules and before the controller body.
- **Console commands run as the system** and skip policies, unless they take an
  actor (`--as=`) — then they authorize explicitly with `Gate::forUser()`.
- **Jobs and listeners never authorize.** The entry point that dispatched them did.
  A job that needs a policy check was dispatched from the wrong place.

---

## Errors

Domain failures are typed exceptions that know how they are presented. Entry points
carry no `try`/`catch`.

```php
namespace App\Exceptions;

class AlreadyPublished extends DomainException
{
    public function __construct(public readonly int $postId)
    {
        parent::__construct("Post {$postId} is already published.");
    }

    public function userMessage(): string
    {
        return __('This post has already been published.');
    }
}
```

- The base `App\Exceptions\DomainException` implements `render(Request $request)`
  once: a `422` JSON body with `userMessage()` for API calls, otherwise a redirect
  back with the message flashed and the input kept. One binding, one place to change
  it. (Livewire presentation: see the Livewire guidelines.)
- **One exception class per rule**, named after the rule, carrying the ids that
  explain it. No generic `BusinessException` with a string.
- Exceptions are for **broken invariants**, not for expected branches. "No results"
  is an empty collection; "not found" is route model binding's 404.
- Anything without a presentation bubbles to the Laravel handler and is a bug.

---

## Comments

**No comment is the default.** Class, method and variable names, plus the types,
say what the code does. A comment that repeats them is noise, and it drifts from
the code it describes.

A comment earns its place only when it explains **why** something surprising is
there — something a careful reader would otherwise get wrong, or "fix":

- a workaround for a framework, package or vendor bug — link the issue;
- a vendor quirk: a field that lies, an undocumented limit, a format that differs
  from the docs;
- ordering or timing that matters and is not visible in the code
  (`// delivered after commit`);
- a branch that looks wrong but is deliberate
  (`// not ours to act on, or a redelivery`);
- a container binding that cannot be avoided — say why (see *Construction*).

Rules:

- **Never narrate the code.** `// save the post` above `$post->save()` says nothing.
- **Needing a comment to explain *what* means a missing name.** Rename the
  variable, or extract a method named after the comment.
- **No docblocks restating the signature** — no `@param Post $post`, no
  `@return void`. Types live in the signature. A docblock is allowed only for what
  PHP types cannot express, such as `@return Collection<int, RegionRevenue>`.
- **No commented-out code.** Delete it; git remembers.
- **No section banners, author tags or changelogs** in code.
- **No `TODO` without a linked issue.**
- **Keep a justified comment short** — one line, next to the line it explains.

---

## Testing

Pest. **Test everything — in priority order.** Coverage goes first to what matters:
the backend behavior users and systems rely on. A gap in tier 1 is a bug; a gap in
tier 4 is a to-do.

| Tier | What | Assert with |
|---|---|---|
| 1 — **backend feature** | every Action through the entry point that really reaches it: HTTP route, console command, job, listener, Livewire component | persisted state (`assertDatabaseHas`, `$model->refresh()`), dispatched events, jobs and notifications (`Event::assertDispatched`, `Queue::assertPushed`), domain exceptions, status codes, redirects, validation errors, JSON (`assertJsonPath`) |
| 2 — domain unit | VOs, enums, model transitions and scopes, casts, DTO named constructors | plain `expect()` |
| 3 — gateways | Gateway + Client per vendor, contract test per adapter | `Http::fake()`, `Http::assertSent()` |
| 4 — frontend | rendered pages and UI behavior | `assertSee`, `assertSeeText`, `assertSeeInOrder`, `assertViewHas`; browser tests (Pest browser plugin) for critical flows |

```php
it('publishes a draft post', function () {
    $author = User::factory()->create();
    $post = Post::factory()->draft()->for($author, 'author')->create();

    $this->actingAs($author)
        ->post(route('posts.publish', $post))
        ->assertRedirect(route('posts.show', $post));

    expect($post->refresh()->status)->toBe(PostStatus::Published);
    Event::assertDispatched(PostPublished::class);
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

it('shows the published status on the post page', function () {
    $post = Post::factory()->published()->create();

    $this->get(route('posts.show', $post))
        ->assertOk()
        ->assertSeeText(PostStatus::Published->label());
});
```

Rules:

- **Every change ships with its tier-1 test first.** A write is proven by the state
  it leaves, the events it dispatches and the exceptions it throws — driven through
  the entry point a user or a system actually hits.
- **Frontend assertions are welcome, and never replace tier 1.** Assert the
  persisted state first, then what the screen shows. A write covered only by
  `assertSee` proves the page, not the rule.
- **Every Action gets at least**: the happy path, one test per invariant and
  business rule it enforces, and — at its entry point — one test for authorization
  denied and one for invalid input.
- **One test per rule.** Do not re-cover an Action's rule from three entry points;
  each extra entry point gets one test proving it authorizes, validates and
  delegates.
- **Events are tested at both ends, plus once end to end.** The emitting Action's
  test fakes the event (`Event::fake([PaymentPaid::class])`) and asserts it was
  dispatched — and not dispatched on a redelivery. Each listener's Action has its
  own tier-1 tests. The wiring gets `Event::assertListening(PaymentPaid::class,
  MarkOrderAsPaid::class)`, and one feature test per flow runs the webhook with
  real listeners (sync queue) and asserts the order paid and the invoice issued.
- **Never hit a real vendor.** Feature tests either swap the gateway factory
  (`$this->instance(PaymentGatewayFactory::class, $fake)`) or `Http::fake()` the
  vendor endpoints, which also exercises the Gateway's translation.
- **A factory per model**, with named states (`draft()`, `published()`,
  `overdue()`). No seeders in tests, no shared fixture data.

---

## Anti-patterns

| Do not | Do |
|---|---|
| `PostService`, `PostManager`, `PostRepository` | one Action per intent |
| `save()` / `update()` / `create()` outside an Action or a model transition | the Action owns the write |
| a controller that queries, transforms, or persists | FormRequest → Action → response |
| effects fired from observers or `booted()` hooks | effects ordered explicitly in the Action |
| business logic in a job's `handle()` | retry config on the job, logic in the Action |
| `$this->authorize()` or validation inside a job | authorize and validate at the entry point |
| a fat listener reacting with rules of its own | listener config + one Action call |
| one method updating payment, order and invoice and sending the email | the Action dispatches `PaymentPaid`; one listener + Action per reaction |
| an event dispatched from a model, observer, controller or component | the Action dispatches it, after commit |
| `PaymentUpdated`, `SendInvoice` as event names | past-tense domain facts: `PaymentPaid`, `InvoiceIssued` |
| `if (! $tenant->invoicing) return;` in a listener | the rule in the Action the listener calls |
| a listener dispatching another event itself | the listener's Action dispatches its own fact |
| a direct call to `IssueInvoice` inside `ReceivePaymentWebhook` | `PaymentPaid` → `IssueInvoiceForPayment` listener |
| an event dispatched again on a redelivered webhook | early return when already applied; dispatch only on the transition |
| a vendor webhook payload reaching an Action | Gateway verifies and translates it into a domain DTO |
| a console command building queries in a loop | read Action, then write Action |
| `DB::transaction()` in a controller or command | transaction inside `handle()` |
| primitives crossing layers (`string $currency`) | VO or string-backed enum |
| `handle(array $data)` / `handle(int $id, string $name, ...)` | one DTO, or models + VOs |
| an Action returning `bool` or an associative array | model, VO, or result DTO |
| a DTO of raw strings | DTO whose fields are VOs, enums and models |
| a DTO that grew a rule | rule on the VO, the model, or the Action |
| `final class PublishPost`, `final class Post` | `final readonly` only on DTOs and VOs |
| `Http::` inside an Action, model, job or controller | Gateway + Client |
| vendor field names leaking past the Gateway | domain DTOs in and out |
| catching `RequestException` in an Action | Gateway maps it to a domain exception |
| a Gateway or Client calling `config()` or looking up the tenant | a Factory reads both and calls `new` |
| `$this->app->bind(PaymentGateway::class, ...)` in a provider | a Factory the Action injects |
| `when()->needs()->give()` to feed credentials | pass them through the Factory |
| `app(...)` / `resolve(...)` in application code | constructor or method injection |
| an interface for a single vendor | Gateway class now, contract with the 2nd vendor |
| an interface shaped by the vendors' feature union | domain-shaped contract, `UnsupportedOperation` for gaps |
| int-backed enums, unbacked enums for stored values | string-backed, snake_case values |
| an Eloquent model for `post_status` | `id` + `label` table, `DB` facade in one attribute |
| a rule reading the lookup table (`->where('label', ...)` for logic) | the rule on the enum |
| storing display text in `label` | `label` = backing value; text from `$status->label()` |
| passing `post_status_id` around | pass the enum; only the model knows the column |
| `scopePublished()` prefix methods | `#[Scope] protected function published()` |
| `->whereRaw('status_id = 3')`, interpolated SQL | scope + builder methods, bindings only |
| `->where('post_status_id', 3)` in an Action | a `#[Scope]` that names the predicate |
| a repository or query-object layer | `Model::query()` composed in the Action |
| an Action returning a `Builder` | return models, collections or VOs |
| one report class with `$groupBy` flags | one Action per report, named after the answer |
| `$post->status = 'published'` from outside | `$post->publish($at)` |
| a quota, config or actor check inside a model method | the check in the Action |
| `config()`, `auth()` or a query inside a model | pass it in, or decide it in the Action |
| an Action re-checking an invariant the model owns | let the model throw |
| business rules in FormRequest `rules()` | FormRequest = shape, Action = rules |
| `try`/`catch` around Actions at entry points | self-rendering domain exception |
| a write covered only by `assertSee` | assert state, events and exceptions first, then the page |
| a feature test hitting a real vendor | swap the gateway factory, or `Http::fake()` |
| static finders on models | scope + call site, or an Action |
| `// publish the post` above `$post->publish($at)` | nothing — the name already says it |
| a comment explaining *what* a block does | a better name, or an extracted method |
| `@param` / `@return` docblocks repeating the types | the typed signature |
| commented-out code | delete it; git remembers |

---

## Review checklist

- [ ] Every write goes through an Action with `handle()` and a transaction.
- [ ] The Action orchestrates: transitions, other aggregates, gateways, events and jobs are explicit calls in `handle()`.
- [ ] No writes from controllers, commands, jobs, listeners, observers or model hooks.
- [ ] Action names are verb + noun; no `*Service` / `*Manager` classes.
- [ ] Actions receive VOs, DTOs or models — never loose primitives, arrays or `request()`.
- [ ] Action returns are models, VOs or result DTOs — never `bool` or an array.
- [ ] DTOs are `final readonly`, in `app/Data/`, with VO/enum fields and named constructors.
- [ ] Only DTOs and VOs are `final`; every other class stays open.
- [ ] No `Http::` outside a Client; every external call goes Gateway → Client.
- [ ] Gateways needing config or tenant data are built by a Factory with `new`; Actions inject the Factory.
- [ ] No container bindings for gateways, no contextual bindings, no `app()`/`resolve()` in application code.
- [ ] Vendor errors become domain exceptions inside the Gateway.
- [ ] Two or more vendors: a domain-shaped contract, one adapter each, selected by a factory.
- [ ] Model transitions guard their invariants before changing state.
- [ ] Models carry domain rules only — no config, no queries, no actor, no events.
- [ ] Every business rule lives in an Action, not on the model or at an entry point.
- [ ] No query building outside scopes and read Actions.
- [ ] All scopes use `#[Scope]`; no `scopeXxx()` prefixes anywhere.
- [ ] No raw `where` — raw appears only for aggregates inside a report Action.
- [ ] Reports are their own Action, named after the answer, returning VOs.
- [ ] Every meaningful column has an enum, VO cast, or native cast.
- [ ] Enums are string-backed and hold every rule about the value.
- [ ] Lookup tables are `id` + `label` only, seeded from the enum, no model.
- [ ] The enum ⇄ lookup mapping is one `Attribute` on the model; no `*_id` leaks out.
- [ ] VOs are `final readonly` with private constructors and named factories.
- [ ] Every entry point: authorize → validate → one Action → present.
- [ ] Controllers are single-action, with a FormRequest carrying `authorize()`.
- [ ] Console commands validate their options and never query directly.
- [ ] Jobs and listeners hold only retry/queue config plus one Action call.
- [ ] Consequences in other aggregates are listeners on a domain event, not direct calls in the emitting Action.
- [ ] Domain events are past-tense facts, dispatched only by Actions, `ShouldDispatchAfterCommit`, payload without behavior.
- [ ] Webhooks: signature verified in `authorize()`, payload translated by the Gateway, Action idempotent, event only on the real transition.
- [ ] FormRequests hold only shape rules.
- [ ] Domain exceptions are typed, per-rule, and render themselves.
- [ ] Every change has a tier-1 backend feature test asserting state, events or exceptions; frontend assertions come on top, never instead.
- [ ] No comments narrating code, no docblocks repeating types, no commented-out code; every remaining comment explains a non-obvious why.
