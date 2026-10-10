import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-[12px] font-medium",
  {
    variants: {
      variant: {
        default: "bg-[#F3F3F3] text-[#4A4A4A]",
        accent: "bg-[#ECEBFA] text-[#2D2A6E]",
        gold: "bg-[#a9812f]/12 text-[#7a5c1f]",
        success: "bg-[#EEF6F1] text-[#1F7A4D]",
        warning: "bg-[#FDF3E6] text-[#8A4B00]",
        danger: "bg-[#FDECEA] text-[#B42318]",
      },
    },
    defaultVariants: { variant: "default" },
  }
);

export interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement>, VariantProps<typeof badgeVariants> {}

export function Badge({ className, variant, ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />;
}
