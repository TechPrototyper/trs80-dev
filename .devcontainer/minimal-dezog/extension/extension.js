const vscode = require('vscode');

class DeZogDebugAdapterDescriptorFactory {
  createDebugAdapterDescriptor(session) {
    const port = session.configuration.port || 49152;
    return new vscode.DebugAdapterServer(port, 127);
  }
}

function activate(context) {
  context.subscriptions.push(
    vscode.debug.registerDebugAdapterDescriptorFactory('dezog', new DeZogDebugAdapterDescriptorFactory())
  );
}

function deactivate() {}

module.exports = { activate, deactivate };
