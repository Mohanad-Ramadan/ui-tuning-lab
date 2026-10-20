import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { HomeScreen } from "./HomeScreen";
import "./styles.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <HomeScreen />
  </StrictMode>,
);
