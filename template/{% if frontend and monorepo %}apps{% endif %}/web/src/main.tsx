import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./app";
import { pageTitle } from "./lib/project";
import "./styles.css";

document.title = pageTitle();

const root = document.getElementById("root");
if (!root) {
  throw new Error("root element #root not found");
}

createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
