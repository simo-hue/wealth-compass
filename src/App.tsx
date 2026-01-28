import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import { Layout } from './components/layout/Layout';
import { Home } from './pages/Home';
import { Features } from './pages/Features';
import { Founder } from './pages/Founder';
import { FAQ } from './pages/FAQ';
import { Tutorial } from './pages/Tutorial';
import { PrivacyPolicy } from './pages/PrivacyPolicy';
import { TermsOfService } from './pages/TermsOfService';

function App() {
  return (
    <Router>
      <Layout>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/features" element={<Features />} />
          <Route path="/founder" element={<Founder />} />
          <Route path="/faq" element={<FAQ />} />
          <Route path="/tutorial" element={<Tutorial />} />
          <Route path="/privacy" element={<PrivacyPolicy />} />
          <Route path="/terms" element={<TermsOfService />} />
        </Routes>
      </Layout>
    </Router>
  );
}

export default App;
