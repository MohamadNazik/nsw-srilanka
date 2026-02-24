import {StrictMode} from 'react'
import {createRoot} from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import "@radix-ui/themes/styles.css";
import {BrowserRouter} from 'react-router-dom';
import {Theme} from '@radix-ui/themes';
import { ErrorBoundary } from './components/ErrorBoundary'
import { AsgardeoProvider } from '@asgardeo/react'

const APP_URL = import.meta.env.VITE_APP_URL || window.location.origin
const CLIENT_ID = import.meta.env.VITE_IDP_CLIENT_ID || 'TRADER_PORTAL_APP'
const IDP_BASE_URL = import.meta.env.VITE_IDP_BASE_URL || 'https://localhost:8090'
const IDP_PLATFORM = import.meta.env.VITE_IDP_PLATFORM || 'AsgardeoV2'
const IDP_SCOPES = import.meta.env.VITE_IDP_SCOPES 
  ? import.meta.env.VITE_IDP_SCOPES.split(',').map((s: string) => s.trim())
  : ["openid", "profile", "email"]

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      <AsgardeoProvider
        clientId={CLIENT_ID}
        baseUrl={IDP_BASE_URL}
        platform={IDP_PLATFORM}
        afterSignInUrl={APP_URL}
        afterSignOutUrl={APP_URL}
        scopes={IDP_SCOPES}
      >
        <Theme>
          <BrowserRouter>
            <App/>
          </BrowserRouter>
        </Theme>
      </AsgardeoProvider>
    </ErrorBoundary>
  </StrictMode>,
)
