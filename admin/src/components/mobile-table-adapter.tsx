"use client";

import { usePathname } from "next/navigation";
import { useEffect } from "react";

function labelDashboardTables() {
  const tables = document.querySelectorAll<HTMLTableElement>(".dashboard-content table");

  tables.forEach((table) => {
    const headerCells = Array.from(
      table.querySelectorAll<HTMLTableCellElement>(":scope > thead > tr:last-child > th"),
    );
    if (headerCells.length < 2) return;

    const labels = headerCells.map((cell, index) => {
      const label = cell.textContent?.replace(/\s+/g, " ").trim();
      return label || (index === headerCells.length - 1 ? "Aktionen" : `Feld ${index + 1}`);
    });

    table.dataset.mobileLayout = "cards";
    table.querySelectorAll<HTMLTableRowElement>(":scope > tbody > tr").forEach((row) => {
      Array.from(row.cells).forEach((cell, index) => {
        if (cell.colSpan > 1) {
          cell.dataset.mobileFullWidth = "true";
          return;
        }
        cell.dataset.mobileLabel = labels[index] ?? `Feld ${index + 1}`;
      });
    });
  });
}

/**
 * Ergänzt die vorhandenen Server-Tabellen nur um mobile Beschriftungen.
 * Dadurch bleiben Desktop-Markup, Daten und Aktionen vollständig erhalten,
 * während CSS dieselben Zeilen auf kleinen Displays als Karten darstellen kann.
 */
export function MobileTableAdapter() {
  const pathname = usePathname();

  useEffect(() => {
    const animationFrame = window.requestAnimationFrame(labelDashboardTables);
    return () => window.cancelAnimationFrame(animationFrame);
  }, [pathname]);

  return null;
}
