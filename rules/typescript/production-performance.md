# Production Performance (Frontend)

> Extends [common/production-performance.md](../common/production-performance.md)
> with React/Next.js/TypeScript-specific patterns.

## 1. React Query Persistence (Instant Cold Starts)

ALWAYS add localStorage persistence for React Query. Users should see cached
data immediately on return visits instead of a loading skeleton.

```typescript
import { PersistQueryClientProvider } from "@tanstack/react-query-persist-client";
import { createSyncStoragePersister } from "@tanstack/query-sync-storage-persister";

// Create persister inside component (NOT module-level) to avoid SSR issues
const [persister] = useState(() => {
  if (typeof window === "undefined") return noopPersister;
  return createSyncStoragePersister({
    storage: window.localStorage,
    key: "app-query-cache",
  });
});

// Exclude admin/ephemeral queries from persistence
const PERSIST_DENYLIST = ["admin", "queue", "audit-logs"];
```

**Required packages:** `@tanstack/react-query-persist-client`, `@tanstack/query-sync-storage-persister`

## 2. Explicit staleTime on Every Query

NEVER leave staleTime as default (0). Every `useQuery` must declare how fresh
the data needs to be.

| Data Type | staleTime | Example |
|-----------|-----------|---------|
| User profile | 5 min | Current user, preferences |
| Lists | 10 min | Tool list, workflow list |
| Detail pages | 10 min | Tool detail, workflow detail |
| Stable reference | 15+ min | Workflows, categories |
| Search results | 30 sec | Search autocomplete |
| Real-time | 0 | Chat messages, notifications |

```typescript
// WRONG: refetches on every mount
useQuery({ queryKey: ["saved-tools"], queryFn: fetchSavedTools });

// CORRECT: respects cache for 10 minutes
useQuery({
  queryKey: ["saved-tools"],
  queryFn: fetchSavedTools,
  staleTime: 10 * 60 * 1000,
});
```

## 3. Scoped Cache Invalidation

NEVER invalidate everything on mutation. Scope to the affected entity type.

```typescript
// WRONG: 5 broad invalidations on single unsave
onSettled: () => {
  queryClient.invalidateQueries({ queryKey: ["saved-items"] });
  queryClient.invalidateQueries({ queryKey: ["saved-items-full"] });
  queryClient.invalidateQueries({ queryKey: ["saved-tools"] });
  queryClient.invalidateQueries({ queryKey: ["saved-tool-ids"] });
  queryClient.invalidateQueries({ queryKey: ["saved-workflow-ids"] });
}

// CORRECT: only invalidate what changed
onSettled: (_data, _error, variables) => {
  if (variables.itemType === "tool") {
    queryClient.invalidateQueries({ queryKey: ["saved-tool-ids"] });
    queryClient.invalidateQueries({ queryKey: ["saved-tools"] });
  } else {
    queryClient.invalidateQueries({ queryKey: ["saved-workflow-ids"] });
  }
  queryClient.invalidateQueries({ queryKey: ["saved-items-full", variables.itemType] });
}
```

## 4. Zustand Selectors (Always)

NEVER destructure the entire store. Always use selectors.

```typescript
// WRONG: re-renders on ANY store change
const { setPlayer, cleanup } = useVideoPlayerStore();

// CORRECT: re-renders only when these specific values change
const setPlayer = useVideoPlayerStore((s) => s.setPlayer);
const cleanup = useVideoPlayerStore((s) => s.cleanup);
```

## 5. Next.js Image Optimization

NEVER use the `unoptimized` prop on `<Image>`. Let Next.js handle
resizing, format conversion (WebP/AVIF), and lazy loading.

```typescript
// WRONG: bypasses all optimization
<Image src={logoUrl} width={48} height={48} unoptimized />

// CORRECT: Next.js optimizes automatically
<Image src={logoUrl} width={48} height={48} alt={name} />
```

**Required:** Configure `remotePatterns` in `next.config.ts` for external image hosts.

## 6. SSE Before Polling

For real-time features, try SSE first with polling as fallback.
NEVER start both simultaneously.

```typescript
// WRONG: double network traffic
startPolling();
connectSSE();

// CORRECT: SSE primary, polling fallback after timeout
connectSSE();
const sseTimeout = setTimeout(() => {
  if (eventSourceRef.current?.readyState !== EventSource.OPEN) {
    startPolling();
  }
}, 5000);
```

**Note:** `EventSource.OPEN` is a static constant (1). Check `readyState`, not `.OPEN`.

## 7. Dynamic Imports for Heavy Components

Components not visible on initial render should be dynamically imported.

```typescript
const AIChatPanel = dynamic(
  () => import("@/components/ai/ai-chat-panel").then((m) => m.AIChatPanel),
  { ssr: false }
);
```

Candidates: chat panels, modals, wizard steps, admin components, charts.

## 8. Avoid Inline Functions in JSX Props

Inline lambdas create new references every render, defeating `React.memo`.

```typescript
// WRONG: new function reference every render
<CompareBar onRemove={(slug) => handleRemove(slug)} />

// CORRECT: stable reference
const handleRemove = useCallback((slug: string) => {
  setCompareSlugs((prev) => prev.filter((s) => s !== slug));
}, []);
<CompareBar onRemove={handleRemove} />
```

## Frontend Performance Checklist

Before marking any page/component as "done":

- [ ] React Query persistence configured (PersistQueryClientProvider)
- [ ] Every useQuery has explicit staleTime
- [ ] Mutations use scoped invalidation (not broad)
- [ ] Zustand stores accessed via selectors only
- [ ] No `unoptimized` on Image components
- [ ] SSE preferred over polling (with fallback)
- [ ] Heavy components dynamically imported
- [ ] No inline functions in frequently-rendered JSX
- [ ] Lists with 20+ items consider virtualization
- [ ] Skeleton loaders match final layout (prevent CLS)
