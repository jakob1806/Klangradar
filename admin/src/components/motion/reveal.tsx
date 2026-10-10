"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";

// Blendet Inhalt beim Hineinscrollen ein (Klasse fw-reveal in globals.css).
// delayMs staffelt mehrere Elemente nebeneinander.
export function Reveal({ children, delayMs = 0, className = "" }: { children: ReactNode; delayMs?: number; className?: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) {
        setVisible(true);
        observer.disconnect();
      }
    }, { threshold: 0.15, rootMargin: "0px 0px -40px 0px" });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return (
    <div ref={ref} data-visible={visible} className={`fw-reveal ${className}`} style={{ transitionDelay: `${delayMs}ms` }}>
      {children}
    </div>
  );
}
