import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-[11px] font-semibold tracking-tight",
  {
    variants: {
      variant: {
        default: "bg-[#EEEEE9] text-[#71717A]",
        accent: "bg-[#ECEBFA] text-[#2D2A6E]",
        gold: "bg-[#a9812f]/12 text-[#7a5c1f]",
        success: "bg-[#DCFCE7] text-[#15803D]",
        warning: "bg-[#FEF3C7] text-[#B45309]",
        danger: "bg-[#FCE7F3] text-[#BE185D]",
      },
    },
    defaultVariants: { variant: "default" },
  }
);

export interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement>, VariantProps<typeof badgeVariants> {}

export function Badge({ className, variant, ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />;
}
