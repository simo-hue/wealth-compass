import { createRoot, hydrateRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";

const container = document.getElementById("root")!;

/**
 * The marketing routes are prerendered to real HTML at build time, so on those
 * pages the container already holds server markup and must be HYDRATED —
 * createRoot would throw that markup away and re-render from scratch, costing a
 * full-page flash and defeating the point of prerendering.
 *
 * /sw/* is not prerendered and arrives with an empty container, so it still
 * takes the createRoot path. Checking the container rather than the route keeps
 * this correct however the prerender manifest changes.
 */
if (container.hasChildNodes()) {
  hydrateRoot(container, <App />);
} else {
  createRoot(container).render(<App />);
}
