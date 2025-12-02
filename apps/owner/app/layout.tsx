import Nav from '../components/Nav';
import { ToastHost } from '../components/Toast';
export const metadata = { 
  title: 'Owner Portal',
  icons: {
    icon: '/favicon.ico',
  },
};
export default function RootLayout({ children }: any) {
  return (
    <html lang="ko">
      <body style={{fontFamily:'system-ui',maxWidth:980,margin:'0 auto',padding:16}}>
        <Nav />
        {children}
        <ToastHost />
      </body>
    </html>
  );
}

