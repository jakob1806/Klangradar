import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-[11px] font-semibold tracking-tight",
  {
    variants: {
      variant: {
        default: "bg-[#15131a]/[0.06] text-[#4a4550]",
        accent: "bg-[#7d1a3a]/10 text-[#7d1a3a]",
        gold: "bg-[#a9812f]/12 text-[#7a5c1f]",
        success: "bg-[#1f7a4d]/12 text-[#175f3c]",
        warning: "bg-[#a9700f]/14 text-[#8a5a0c]",
        danger: "bg-[#b3273e]/10 text-[#961f33]",
      },
    },
    defaultVariants: { variant: "default" },
  }
);

export interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement>, VariantProps<typeof badgeVariants> {}

export function Badge({ className, variant, ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />;
}
