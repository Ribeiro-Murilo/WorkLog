import React from "react";
import ReactDOM from "react-dom/client";
import { DashboardApp } from "./ui/DashboardApp";
import { NotchApp } from "./ui/NotchApp";

const isNotchRoute = window.location.hash.startsWith("#/notch");

if (isNotchRoute) {
  document.documentElement.classList.add("notch-mode");
  document.body.classList.add("notch-mode");
}

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    {isNotchRoute ? <NotchApp /> : <DashboardApp />}
  </React.StrictMode>
);
