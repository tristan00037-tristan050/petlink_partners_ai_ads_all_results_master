'use client';
import { useRouter, usePathname } from 'next/navigation';
import { useEffect, useState } from 'react';

export default function RequireAuth({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [checked, setChecked] = useState(false);

  useEffect(() => {
    let cancelled = false;
    
    (async () => {
      try {
        const res = await fetch('/api/bff/me', { credentials: 'include' });
        
        if (res.status === 401) throw new Error('unauth');
        if (!res.ok) throw new Error('error');
        
        if (!cancelled) setChecked(true);
      } catch {
        if (!cancelled) {
          router.replace(`/login?next=${encodeURIComponent(pathname)}`);
        }
      }
    })();

    return () => { cancelled = true; };
  }, [pathname, router]);

  if (!checked) return <div aria-busy="true">Loading…</div>;

  return <>{children}</>;
}
