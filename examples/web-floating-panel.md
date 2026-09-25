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
  useEffect(() => {
    if (!LAB) return;
    const onKey = (e) => {
      if (e.ctrlKey && e.shiftKey && e.key === "L") setOpen((v) => !v);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);
  if (!LAB) return <Feature />;
  return (
    <>
      <Feature />
      {open && (
        <div popover="auto" data-tuning-lab>
          <LabControls />
        </div>
      )}
    </>
  );
}
```

Fallback when popover is unavailable: `<details><summary>Lab</summary>`
with the same conditionally mounted controls.
