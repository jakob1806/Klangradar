import * as React from "react";
import { cn } from "@/lib/utils";

export const Input = React.forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(
  ({ className, ...props }, ref) => (
    <input
      ref={ref}
      className={cn(
        "flex h-9 w-full rounded-lg border border-black/10 bg-white px-3 text-sm text-[#15131a] placeholder:text-[#726c78] transition focus-visible:border-[#7d1a3a] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#7d1a3a]/25 disabled:cursor-not-allowed disabled:opacity-50",
        className
      )}
      {...props}
    />
  )
);
Input.displayName = "Input";

export const Textarea = React.forwardRef<HTMLTextAreaElement, React.TextareaHTMLAttributes<HTMLTextAreaElement>>(
  ({ className, ...props }, ref) => (
    <textarea
      ref={ref}
      className={cn(
        "flex min-h-20 w-full rounded-lg border border-black/10 bg-white px-3 py-2 text-sm text-[#15131a] placeholder:text-[#726c78] transition focus-visible:border-[#7d1a3a] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#7d1a3a]/25 disabled:cursor-not-allowed disabled:opacity-50",
        className
      )}
      {...props}
    />
  )
);
Textarea.displayName = "Textarea";
