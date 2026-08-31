import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/utils";

// Eigenständige Farb-/Formsprache fürs Veranstalterportal (Weinrot #7d1a3a
// als einzige Akzentfarbe, Radius-Schema 10px für Buttons) — bewusst NICHT
// das Apple-Blau/Pill-Schema des internen Redaktions-Dashboards. Literale
// Hex-/Tailwind-Farbwerte statt CSS-Custom-Properties: Tailwind v4s
// lightningcss-Minifizierung verwirft eigene :root-Variablen beim Build
// kommentarlos (siehe Begründung in globals.css).
const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-[10px] text-sm font-semibold transition disabled:pointer-events-none disabled:opacity-40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#7d1a3a]/35 [&_svg]:size-4 [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        default: "bg-[#7d1a3a] text-white hover:bg-[#8f1f44] active:bg-[#6c1631]",
        secondary: "bg-[#15131a]/[0.05] text-[#15131a] hover:bg-[#15131a]/[0.09]",
        outline: "border border-[#15131a]/15 bg-white text-[#15131a] hover:bg-[#15131a]/[0.03]",
        ghost: "text-[#15131a] hover:bg-[#15131a]/[0.05]",
        destructive: "bg-[#b3273e] text-white hover:bg-[#c22e46]",
        link: "text-[#7d1a3a] underline-offset-4 hover:underline",
      },
      size: {
        default: "h-10 px-4",
        sm: "h-8 px-3 text-[13px]",
        lg: "h-11 px-6 text-[15px]",
        icon: "size-10",
      },
    },
    defaultVariants: { variant: "default", size: "default" },
  }
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button";
    return <Comp ref={ref} className={cn(buttonVariants({ variant, size }), className)} {...props} />;
  }
);
Button.displayName = "Button";
