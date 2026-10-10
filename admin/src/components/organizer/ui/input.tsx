import * as React from "react";
import { cn } from "@/lib/utils";

export const Input = React.forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(
  ({ className, ...props }, ref) => (
    <input
      ref={ref}
      className={cn(
        "flex h-9 w-full rounded-lg border border-[#DADADA] bg-white px-3 text-sm text-[#111111] placeholder:text-[#6B6B6B] transition hover:border-[#BDBDBD] focus-visible:border-[#111111] focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-[#2D2A6E]/12 disabled:cursor-not-allowed disabled:opacity-50",
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
        "flex min-h-20 w-full rounded-lg border border-[#DADADA] bg-white px-3 py-2 text-sm text-[#111111] placeholder:text-[#6B6B6B] transition hover:border-[#BDBDBD] focus-visible:border-[#111111] focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-[#2D2A6E]/12 disabled:cursor-not-allowed disabled:opacity-50",
        className
      )}
      {...props}
    />
  )
);
Textarea.displayName = "Textarea";
