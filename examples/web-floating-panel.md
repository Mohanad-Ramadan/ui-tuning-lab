# Example — Web floating panel (verified tier)

Conditionally mounted `popover="auto"` lab. Zero cost when closed:
unmounted, no observers, no listeners.

```jsx
const LAB =
  import.meta.env.DEV &&
  (new URLSearchParams(location.search).has("lab") ||
    localStorage.getItem("ui-tuning-lab") === "1");

function App() {
  const [open, setOpen] = useState(false);
  const panelRef = useRef(null);
  useEffect(() => {
    if (!LAB || !open) return;
    const el = panelRef.current;
    if (!el) return;
    if (typeof el.showPopover === "function") el.showPopover();
    const onToggle = (e) => {
      if (e.newState === "closed") setOpen(false);
    };
    el.addEventListener("toggle", onToggle);
    return () => {
      el.removeEventListener("toggle", onToggle);
      if (typeof el.hidePopover === "function" && el.matches(":popover-open")) {
        el.hidePopover();
      }
    };
  }, [open]);
  if (!LAB) return <Feature />;
  return (
    <>
      <Feature />
      <button type="button" onClick={() => setOpen(true)}>
        Open lab
      </button>
      {open && (
        <div ref={panelRef} popover="auto" data-tuning-lab>
          <LabControls />
        </div>
      )}
    </>
  );
}
```

Fallback when popover is unavailable: `<details><summary>Lab</summary>`
with the same conditionally mounted controls.
