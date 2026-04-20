# Async State Safety

> Rules for correctness of UI state when async backend work is in flight.
> Every one of these is a real race or drift bug that shipped, hit users,
> and had to be hot-patched. Apply them FROM THE START.

## 1. Fire the mutation BEFORE the UI transition (CRITICAL)

Never set local UI state to "in progress" before the backend has been
told that work has started. The gap between `setState(next)` and the
HTTP request reaching the backend is a race window; any user action
(click a nav link, close the tab, Cmd+R) during that gap leaves the
client with lost state and the backend unaware that anything started.

```
WRONG:  setStep(6);                             // UI says "building..."
        await generateMutation.mutateAsync();   // ← race window here
        // if user clicks away during this await, the backend session
        // stays in wizard_in_progress and the resume flow sends them
        // back to step 5 on return

CORRECT: await generateMutation.mutateAsync();  // backend commits first
        setStep(6);                             // UI transitions only
                                                // after backend confirms
```

The UX cost is a ~200-300ms wait before the transition; cover it with a
spinner on the button that fired the mutation so the user sees their
click registered. The reliability gain is enormous: the resume flow,
the sidebar badge, the completion toast all become consistent because
the backend state is the source of truth.

**This rule applies to any mutation that:**
- Starts a long-running async operation
- Changes which "step" or "screen" the user is on
- Is a prerequisite for the next UI state being meaningful

## 2. Wall-clock anchoring for long-running progress

Any UI that shows elapsed time, progress stages, or a count of seconds
for an async operation must be anchored to a server-provided timestamp,
not a local `setInterval` or `setTimeout` that resets on component
unmount/remount.

```
WRONG:
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setElapsedSeconds(s => s + 1), 1000);
    return () => clearInterval(id);
  }, []);
  // User navigates away at 15s → remount → restarts from 0s

CORRECT:
  // Server provides generation_started_at (e.g., updated_at when
  // status was set to 'running' on the backend)
  const startEpochMs = useMemo(() => {
    return generationStartedAt
      ? new Date(generationStartedAt).getTime()
      : Date.now();
  }, [generationStartedAt]);

  const [nowMs, setNowMs] = useState(() => Date.now());
  useEffect(() => {
    const id = setInterval(() => setNowMs(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  const elapsedSeconds = Math.floor((nowMs - startEpochMs) / 1000);
  const activeStage = resolveStageFromElapsed(nowMs - startEpochMs);
```

When the user leaves and comes back, `generationStartedAt` is still
pinned to the real backend start time. On remount, the first render
computes the true elapsed gap. The progress bar picks up where the
backend actually is, not where the local timer restarts.

Applies to:
- Loading screens with multi-stage progress
- Upload/download progress bars
- Any "~Xs elapsed" counter
- Any animation that should persist across remounts

## 3. Resume flow for any multi-step async UX

Any flow where a user can start async work and navigate away (before
completion) must support resuming. The full pattern:

1. **Backend**: expose a `GET /sessions/active` endpoint (or equivalent)
   that returns the user's most recent resumable session by status, with
   an auto-fail step for sessions stuck past a reasonable timeout.

2. **Frontend mount effect**: on the flow's page, call the active-session
   endpoint before rendering Step 1. If a session comes back:
   - `status === "running"` → jump to the loading screen
   - `status === "completed"` → jump to results
   - `status === "in_progress"` → hydrate form state, jump to last
     completed step
   - `null` → fresh start

3. **localStorage mirror**: when a session ID is created, write it to
   `localStorage["<feature>:active-session"]` so a hard reload can
   recover even if the backend call fails.

4. **URL param**: also write `?session=<id>` so the URL is shareable
   and survives new-tab recovery. Use `router.replace`, not `push`,
   so the back button doesn't get polluted.

5. **Stuck-session safety net**: on the backend, if a session is
   `status=running` but its `updated_at` is older than a reasonable
   threshold (e.g., 10 minutes for a task expected to finish in 1-5),
   auto-fail it before returning. Prevents "eternal spinner" when a
   dev-mode inline task dies mid-run.

6. **Beforeunload guard**: for multi-step forms that span more than
   one step, attach a `beforeunload` listener when the user has
   answered at least one step so the browser prompts before tab close.

Apply this pattern to ANY flow where:
- Backend work takes > 10 seconds
- The user might reasonably navigate away while waiting
- Losing state would require the user to re-enter data

## 4. Scoped cache invalidation, not broad

When a mutation completes, invalidate only the React Query keys the
mutation actually affected. Broad invalidation re-fetches unrelated
data and blows away optimistic updates on other parts of the page.

```
WRONG:  onSuccess: () => {
          // This refetches everything under ["tools"], including unrelated
          // tool detail pages that are still visible in the cache
          queryClient.invalidateQueries({ queryKey: ["tools"] });
        }

CORRECT: onSettled: (data, err, variables) => {
          // Scope to the affected entity type
          if (variables.itemType === "tool") {
            queryClient.invalidateQueries({
              queryKey: ["saved-tool-ids"]
            });
            queryClient.invalidateQueries({
              queryKey: ["saved-items-full", "tool"]
            });
          }
        }
```

## 5. Optimistic updates on user-driven mutations

For mutations where the server answer is trusted (save, favorite, like,
rating), use `onMutate` to update the cache immediately. The user sees
their click register without waiting for the round-trip.

```
useMutation({
  mutationFn: toggleSave,
  onMutate: async ({ id }) => {
    await queryClient.cancelQueries({ queryKey: ["saved-items"] });
    const previous = queryClient.getQueryData(["saved-items"]);
    queryClient.setQueryData(["saved-items"], (old) => toggle(old, id));
    return { previous };  // rollback snapshot
  },
  onError: (_err, _vars, context) => {
    queryClient.setQueryData(["saved-items"], context.previous);
  },
  onSettled: () => {
    queryClient.invalidateQueries({ queryKey: ["saved-items"] });
  },
});
```

## 6. SSE > polling for real-time updates

For real-time feeds (new content, live collaboration, presence), use
Server-Sent Events with a 30-60s polling fallback. Don't run both
simultaneously.

```
WRONG:  useQuery({ refetchInterval: 2 * 60 * 1000 })
        // refetches every 2 minutes regardless of whether anything changed

CORRECT: function useRealtimeDashboard() {
          const queryClient = useQueryClient();

          useEffect(() => {
            const es = new EventSource("/api/events?token=...");
            es.addEventListener("new_content", () => {
              queryClient.invalidateQueries({ queryKey: ["dashboard"] });
            });
            return () => es.close();
          }, []);
        }
        // useQuery has no refetchInterval; SSE drives invalidation
```

On SSE connection failure, fall back to polling a lightweight
`/check-new?since=<ts>` endpoint every 30s.

## 7. Mutation + navigation = discard guard

When a user has filled out a multi-step form and could lose state by
closing the tab, attach a `beforeunload` listener while the form is
"dirty" (has user input past step 1 and not yet submitted).

```
useEffect(() => {
  const hasUnsavedWork = step >= 2 && step <= formEndStep;
  if (!hasUnsavedWork) return;

  const handler = (e: BeforeUnloadEvent) => {
    e.preventDefault();
    e.returnValue = "";  // modern browsers ignore the string and
                         // show their own localized prompt
  };
  window.addEventListener("beforeunload", handler);
  return () => window.removeEventListener("beforeunload", handler);
}, [step]);
```

Pair with the resume flow (#3) so in-app SPA navigation (sidebar clicks)
still recovers the state even though beforeunload doesn't fire for those.

## 8. Zustand selectors, not destructure

Never destructure an entire Zustand store in a component — every store
update will re-render the component.

```
WRONG:  const { setPlayer, cleanup } = useVideoPlayerStore();
        // re-renders on EVERY store update, even unrelated fields

CORRECT: const setPlayer = useVideoPlayerStore((s) => s.setPlayer);
        const cleanup = useVideoPlayerStore((s) => s.cleanup);
        // re-renders only when these specific fields change
```

## 9. Stable function references for frequently-rendered JSX

Components rendered in large lists (cards, rows, grid cells) must not
receive inline lambda props. Each render creates a new function reference
and defeats `React.memo`.

```
WRONG:  {tools.map(tool => (
          <ToolCard onRemove={(id) => handleRemove(id)} tool={tool} />
          // ↑ new function every render
        ))}

CORRECT: const handleRemove = useCallback((id: string) => {
          setTools((prev) => prev.filter((t) => t.id !== id));
        }, []);
        {tools.map(tool => (
          <ToolCard onRemove={handleRemove} tool={tool} />
        ))}
```

## Async State Safety Checklist

Before marking any async feature as "done":

- [ ] Mutations fire BEFORE UI state transitions to "in progress"
- [ ] Long-running progress UIs anchor to server timestamps
- [ ] Multi-step async flows have a resume-from-active-session flow
- [ ] Backend has a stuck-session auto-fail for the primary flow
- [ ] localStorage + URL param persist critical session IDs
- [ ] beforeunload guard on dirty multi-step forms
- [ ] React Query invalidations are scoped, not broad
- [ ] Optimistic updates where the server answer is trusted
- [ ] Real-time features use SSE, not polling
- [ ] Zustand stores are accessed via selectors only
- [ ] No inline lambdas in list item props
