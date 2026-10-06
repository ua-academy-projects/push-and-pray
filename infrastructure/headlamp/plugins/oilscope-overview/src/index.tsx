import { registerRoute, registerSidebarEntry } from '@kinvolk/headlamp-plugin/lib';
import { overviewRoute, overviewSidebarEntry } from './lib/registration';
import { OverviewPage } from './OverviewPage';

registerSidebarEntry(overviewSidebarEntry);

registerRoute({ ...overviewRoute, component: OverviewPage });
