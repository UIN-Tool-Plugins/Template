package com.example.filemanager;

import android.content.Context;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.io.File;

public class FileManagerPlugin implements com.UIN.Tool.plugin.PluginInterface {

    private Context context;
    private LinearLayout container;

    @Override
    public View onCreateView(Context context, ViewGroup container, Bundle savedInstanceState) {
        this.context = context;
        this.container = new LinearLayout(context);
        this.container.setOrientation(LinearLayout.VERTICAL);
        this.container.setPadding(32, 32, 32, 32);

        TextView title = new TextView(context);
        title.setText("文件管理器 (Native Plugin)");
        title.setTextSize(20);
        title.setPadding(0, 0, 0, 24);
        this.container.addView(title);

        File pluginDir = new File("/storage/emulated/0/UIN_Tool/plugins");
        if (!pluginDir.exists()) pluginDir.mkdirs();

        TextView pathInfo = new TextView(context);
        pathInfo.setText("路径: " + pluginDir.getAbsolutePath());
        pathInfo.setTextSize(12);
        pathInfo.setPadding(0, 0, 0, 16);
        this.container.addView(pathInfo);

        listFiles(pluginDir, this.container, 0);

        return this.container;
    }

    private void listFiles(File dir, LinearLayout parent, int depth) {
        if (!dir.exists() || !dir.isDirectory()) return;

        File[] files = dir.listFiles();
        if (files == null) return;

        for (File file : files) {
            if (file.getName().startsWith(".")) continue;

            LinearLayout row = new LinearLayout(context);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setPadding(depth * 32, 4, 0, 4);

            TextView icon = new TextView(context);
            icon.setText(file.isDirectory() ? "📁 " : "📄 ");
            icon.setTextSize(14);
            row.addView(icon);

            TextView name = new TextView(context);
            name.setText(file.getName());
            name.setTextSize(14);
            row.addView(name);

            parent.addView(row);

            if (file.isDirectory()) {
                listFiles(file, parent, depth + 1);
            }
        }
    }

    @Override
    public void onResume() {}

    @Override
    public void onPause() {}

    @Override
    public void onDestroy() {}

    @Override
    public boolean onBackPressed() {
        return false;
    }

    @Override
    public Bundle onSaveInstanceState() {
        return null;
    }

    @Override
    public void onHostEvent(String event, Bundle data) {}
}
