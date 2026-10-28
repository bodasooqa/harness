import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./app";
import "./styles/globals.css";

const root = document.getElementById("root");
if (!root) {
  throw new Error("не найден корневой элемент #root");
}

createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
