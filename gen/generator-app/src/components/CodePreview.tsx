import React, { useState } from 'react';

interface CodePreviewProps {
  code: string;
}

export const CodePreview: React.FC<CodePreviewProps> = ({ code }) => {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (err) {
      console.error('Failed to copy code: ', err);
    }
  };

  const handleDownload = () => {
    const blob = new Blob([code], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'eulsukdo_example_top.sv';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  };

  return (
    <div className="panel code-panel">
      <div className="panel-header">
        <h2 className="panel-title">Generated SV Wrapper</h2>
        <div className="button-group">
          <button className="btn" onClick={handleCopy}>
            {copied ? 'Copied!' : 'Copy Code'}
          </button>
          <button className="btn btn-primary" onClick={handleDownload}>
            Download SV
          </button>
        </div>
      </div>
      <div className="code-container">
        <pre className="code-pre">
          {code}
        </pre>
      </div>
    </div>
  );
};
